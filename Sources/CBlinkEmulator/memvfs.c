// memvfs.c — Pure in-memory VFS device for blink's VFS layer.
//
// Implements a blink VfsSystem called "memfs" backed by flatvfs_t (flat array
// of file/dir/symlink entries). Provides a read-only base filesystem with a
// write overlay for mutations (mkdir, write, unlink, symlink, rename, chmod).
//
// The overlay is a simple linked list checked before the base flatvfs.

#include "include/CBlinkEmulator.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>

#include "blink/vfs.h"
#include "blink/errno.h"
#include "blink/hostfs.h"
#include "blink/devfs.h"
#include "blink/procfs.h"
#include "blink/dll.h"
#include "blink/thread.h"
#include "blink/types.h"

// ── Forward declarations for VfsOps ─────────────────────────────────────────

static int MemvfsInit(const char *, u64, const void *, struct VfsDevice **,
                      struct VfsMount **);
static int MemvfsFreeinfo(void *);
static int MemvfsFreedevice(void *);
static int MemvfsFinddir(struct VfsInfo *, const char *, struct VfsInfo **);
static int MemvfsTraverse(struct VfsInfo **, const char **, struct VfsInfo *);
static ssize_t MemvfsReadlink(struct VfsInfo *, char **);
static int MemvfsMkdir(struct VfsInfo *, const char *, mode_t);
static int MemvfsOpen(struct VfsInfo *, const char *, int, int,
                      struct VfsInfo **);
static int MemvfsAccess(struct VfsInfo *, const char *, mode_t, int);
static int MemvfsStat(struct VfsInfo *, const char *, struct stat *, int);
static int MemvfsFstat(struct VfsInfo *, struct stat *);
static int MemvfsChmod(struct VfsInfo *, const char *, mode_t, int);
static int MemvfsFchmod(struct VfsInfo *, mode_t);
static int MemvfsChown(struct VfsInfo *, const char *, uid_t, gid_t, int);
static int MemvfsFchown(struct VfsInfo *, uid_t, gid_t);
static int MemvfsFtruncate(struct VfsInfo *, off_t);
static int MemvfsClose(struct VfsInfo *);
static int MemvfsLink(struct VfsInfo *, const char *, struct VfsInfo *,
                      const char *, int);
static int MemvfsUnlink(struct VfsInfo *, const char *, int);
static ssize_t MemvfsRead(struct VfsInfo *, void *, size_t);
static ssize_t MemvfsWrite(struct VfsInfo *, const void *, size_t);
static ssize_t MemvfsPread(struct VfsInfo *, void *, size_t, off_t);
static ssize_t MemvfsPwrite(struct VfsInfo *, const void *, size_t, off_t);
static ssize_t MemvfsReadv(struct VfsInfo *, const struct iovec *, int);
static ssize_t MemvfsWritev(struct VfsInfo *, const struct iovec *, int);
static ssize_t MemvfsPreadv(struct VfsInfo *, const struct iovec *, int, off_t);
static ssize_t MemvfsPwritev(struct VfsInfo *, const struct iovec *, int,
                              off_t);
static off_t MemvfsSeek(struct VfsInfo *, off_t, int);
static int MemvfsFsync(struct VfsInfo *);
static int MemvfsFdatasync(struct VfsInfo *);
static int MemvfsFlock(struct VfsInfo *, int);
static int MemvfsDup(struct VfsInfo *, struct VfsInfo **);
static int MemvfsOpendir(struct VfsInfo *, struct VfsInfo **);
#ifdef HAVE_SEEKDIR
static void MemvfsSeekdir(struct VfsInfo *, long);
static long MemvfsTelldir(struct VfsInfo *);
#endif
static struct dirent *MemvfsReaddir(struct VfsInfo *);
static void MemvfsRewinddir(struct VfsInfo *);
static int MemvfsClosedir(struct VfsInfo *);
static int MemvfsRename(struct VfsInfo *, const char *, struct VfsInfo *,
                        const char *);
static int MemvfsUtime(struct VfsInfo *, const char *,
                       const struct timespec[2], int);
static int MemvfsFutime(struct VfsInfo *, const struct timespec[2]);
static int MemvfsSymlink(const char *, struct VfsInfo *, const char *);
static int MemvfsFcntl(struct VfsInfo *, int, va_list);
static int MemvfsIoctl(struct VfsInfo *, unsigned long, const void *);
static void *MemvfsMmap(struct VfsInfo *, void *, size_t, int, int, off_t);
static int MemvfsMunmap(struct VfsInfo *, void *, size_t);
static int MemvfsMprotect(struct VfsInfo *, void *, size_t, int);
static int MemvfsMsync(struct VfsInfo *, void *, size_t, int);

// ── Data structures ─────────────────────────────────────────────────────────

// Write overlay entry — simple linked list of created/written/deleted entries.
struct MemvfsOverlayEntry {
    char *path;
    uint8_t *data;
    size_t data_size;
    size_t data_capacity;
    mode_t mode;
    int type;              // FLATVFS_FILE, FLATVFS_DIR, FLATVFS_SYMLINK, or -1 for deleted
    char *symlink_target;
    struct MemvfsOverlayEntry *next;
    struct MemvfsOverlayEntry *hash_next;
};

#define MEMVFS_DELETED (-1)

struct MemvfsBasePathIndexEntry {
    const char *path;
    int entry_idx;
    struct MemvfsBasePathIndexEntry *next;
};

struct MemvfsBaseDirChild {
    char *name;
    struct MemvfsBaseDirChild *next;
};

struct MemvfsBaseDirIndexEntry {
    char *path;
    struct MemvfsBaseDirChild *children;
    struct MemvfsBaseDirIndexEntry *next;
};

// Per-file state stored in VfsInfo->data for open files.
struct MemvfsFileData {
    int entry_idx;              // Index into flatvfs_t->entries (-1 for root, -2 for overlay)
    size_t read_offset;         // Current read/write position
    struct MemvfsOverlayEntry *overlay_entry; // Non-NULL if this is an overlay file
    int flags;                  // Open flags (O_RDONLY, O_WRONLY, O_RDWR, etc.)
};

// Per-directory state stored in VfsInfo->data for open directories.
struct MemvfsDirData {
    struct MemvfsFileData file;
    char *dir_path;             // Normalized directory path (e.g. "" for root, "bin" for /bin)
    size_t dir_path_len;
    int readdir_pos;            // Current position for readdir iteration
    // Collected child names for readdir
    char **children;
    int children_count;
    int children_capacity;
};

// Per-device state.
struct MemvfsDeviceData {
    const flatvfs_t *base;
    struct MemvfsOverlayEntry *overlay;
    pthread_mutex_t overlay_lock;
    struct MemvfsBasePathIndexEntry **base_path_buckets;
    size_t base_path_bucket_count;
    struct MemvfsBaseDirIndexEntry **base_dir_buckets;
    size_t base_dir_bucket_count;
    struct MemvfsOverlayEntry **overlay_buckets;
    size_t overlay_bucket_count;
};

// ── Global VfsSystem ────────────────────────────────────────────────────────

struct VfsSystem g_omni_memfs = {
    .name = "memfs",
    .nodev = true,
    .ops = {
        .Init = MemvfsInit,
        .Freeinfo = MemvfsFreeinfo,
        .Freedevice = MemvfsFreedevice,
        .Finddir = MemvfsFinddir,
        .Readlink = MemvfsReadlink,
        .Mkdir = MemvfsMkdir,
        .Open = MemvfsOpen,
        .Access = MemvfsAccess,
        .Stat = MemvfsStat,
        .Fstat = MemvfsFstat,
        .Chmod = MemvfsChmod,
        .Fchmod = MemvfsFchmod,
        .Chown = MemvfsChown,
        .Fchown = MemvfsFchown,
        .Ftruncate = MemvfsFtruncate,
        .Close = MemvfsClose,
        .Link = MemvfsLink,
        .Unlink = MemvfsUnlink,
        .Read = MemvfsRead,
        .Write = MemvfsWrite,
        .Pread = MemvfsPread,
        .Pwrite = MemvfsPwrite,
        .Readv = MemvfsReadv,
        .Writev = MemvfsWritev,
        .Preadv = MemvfsPreadv,
        .Pwritev = MemvfsPwritev,
        .Seek = MemvfsSeek,
        .Fsync = MemvfsFsync,
        .Fdatasync = MemvfsFdatasync,
        .Flock = MemvfsFlock,
        .Fcntl = MemvfsFcntl,
        .Ioctl = MemvfsIoctl,
        .Dup = MemvfsDup,
        .Opendir = MemvfsOpendir,
#ifdef HAVE_SEEKDIR
        .Seekdir = MemvfsSeekdir,
        .Telldir = MemvfsTelldir,
#endif
        .Readdir = MemvfsReaddir,
        .Rewinddir = MemvfsRewinddir,
        .Closedir = MemvfsClosedir,
        .Rename = MemvfsRename,
        .Utime = MemvfsUtime,
        .Futime = MemvfsFutime,
        .Symlink = MemvfsSymlink,
        .Mmap = MemvfsMmap,
        .Munmap = MemvfsMunmap,
        .Mprotect = MemvfsMprotect,
        .Msync = MemvfsMsync,
        // Socket/pipe/mmap/terminal ops are NULL — not supported on memfs.
        // blink will fall back to hostfs for those.
    },
};

// ── Helpers ─────────────────────────────────────────────────────────────────

// Build a full path from a parent VfsInfo and a child name.
// Returns allocated string. Root is represented as "".
// Path components have no leading slash. E.g. root="", child of root "bin"="bin",
// child of "bin" named "sh" = "bin/sh".
static char *memvfs_build_path(struct VfsInfo *parent, const char *name) {
    int is_absolute = 0;

    while (name && name[0] == '/') {
        is_absolute = 1;
        ++name;
    }

    if (!parent || !parent->data) {
        if (!name || name[0] == '\0') return strdup("");
        return strdup(name);
    }

    if (is_absolute) {
        if (!name || name[0] == '\0') return strdup("");
        return strdup(name);
    }

    // Get parent's path from its data
    struct MemvfsFileData *pdata = (struct MemvfsFileData *)parent->data;
    const char *parent_path = NULL;

    // For root node (entry_idx == -1), parent_path is ""
    if (pdata->entry_idx == -1) {
        parent_path = "";
    } else if (pdata->overlay_entry) {
        parent_path = pdata->overlay_entry->path;
    } else {
        struct MemvfsDeviceData *devdata =
            (struct MemvfsDeviceData *)parent->device->data;
        if (pdata->entry_idx >= 0 &&
            pdata->entry_idx < devdata->base->entry_count) {
            parent_path = devdata->base->entries[pdata->entry_idx].path;
        }
    }

    if (!parent_path) return strdup(name ? name : "");

    if (!name || name[0] == '\0') return strdup(parent_path);

    size_t plen = strlen(parent_path);
    if (plen == 0) return strdup(name);

    size_t nlen = strlen(name);
    char *result = malloc(plen + 1 + nlen + 1);
    if (!result) return NULL;
    memcpy(result, parent_path, plen);
    result[plen] = '/';
    memcpy(result + plen + 1, name, nlen);
    result[plen + 1 + nlen] = '\0';
    return result;
}

// Get the path string for a VfsInfo node.
static const char *memvfs_get_path(struct VfsInfo *info) {
    if (!info || !info->data) return "";
    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    if (fdata->entry_idx == -1) return "";
    if (fdata->overlay_entry) return fdata->overlay_entry->path;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;
    if (fdata->entry_idx >= 0 &&
        fdata->entry_idx < devdata->base->entry_count) {
        return devdata->base->entries[fdata->entry_idx].path;
    }
    return "";
}

static uint64_t memvfs_hash_path(const char *path) {
    uint64_t hash = 1469598103934665603ULL;
    const unsigned char *p = (const unsigned char *)path;
    while (*p) {
        hash ^= (uint64_t)*p++;
        hash *= 1099511628211ULL;
    }
    return hash;
}

static size_t memvfs_bucket_count(size_t entry_count) {
    size_t count = 64;
    while (count < entry_count * 2) {
        count <<= 1;
    }
    return count;
}

static struct MemvfsBaseDirIndexEntry *
memvfs_base_dir_lookup(struct MemvfsDeviceData *devdata, const char *path) {
    size_t bucket;
    struct MemvfsBaseDirIndexEntry *entry;

    if (!devdata->base_dir_buckets) return NULL;
    bucket = (size_t)(memvfs_hash_path(path) & (devdata->base_dir_bucket_count - 1));
    for (entry = devdata->base_dir_buckets[bucket]; entry; entry = entry->next) {
        if (strcmp(entry->path, path) == 0) {
            return entry;
        }
    }
    return NULL;
}

static struct MemvfsBaseDirIndexEntry *
memvfs_base_dir_get_or_create(struct MemvfsDeviceData *devdata, const char *path) {
    size_t bucket;
    struct MemvfsBaseDirIndexEntry *entry;

    entry = memvfs_base_dir_lookup(devdata, path);
    if (entry) return entry;

    entry = calloc(1, sizeof(*entry));
    if (!entry) return NULL;
    entry->path = strdup(path);
    if (!entry->path) {
        free(entry);
        return NULL;
    }

    bucket = (size_t)(memvfs_hash_path(path) & (devdata->base_dir_bucket_count - 1));
    entry->next = devdata->base_dir_buckets[bucket];
    devdata->base_dir_buckets[bucket] = entry;
    return entry;
}

static void memvfs_base_dir_add_child(struct MemvfsDeviceData *devdata,
                                      const char *dir_path,
                                      const char *child_name) {
    struct MemvfsBaseDirIndexEntry *dir_entry;
    struct MemvfsBaseDirChild *child;

    dir_entry = memvfs_base_dir_get_or_create(devdata, dir_path);
    if (!dir_entry) return;
    for (child = dir_entry->children; child; child = child->next) {
        if (strcmp(child->name, child_name) == 0) {
            return;
        }
    }
    child = calloc(1, sizeof(*child));
    if (!child) return;
    child->name = strdup(child_name);
    if (!child->name) {
        free(child);
        return;
    }
    child->next = dir_entry->children;
    dir_entry->children = child;
}

static void memvfs_base_index_path_components(struct MemvfsDeviceData *devdata,
                                              const char *path) {
    const char *segment = path;
    const char *slash;
    size_t prefix_len = 0;
    char name[VFS_NAME_MAX];
    char *parent_path;

    if (!path || !path[0]) return;

    for (;;) {
        slash = strchr(segment, '/');
        if (slash) {
            if ((size_t)(slash - segment) >= sizeof(name)) return;
            memcpy(name, segment, (size_t)(slash - segment));
            name[slash - segment] = '\0';
        } else {
            if (strlen(segment) >= sizeof(name)) return;
            strcpy(name, segment);
        }

        if (prefix_len == 0) {
            parent_path = strdup("");
        } else {
            parent_path = strndup(path, prefix_len);
        }
        if (!parent_path) return;
        memvfs_base_dir_add_child(devdata, parent_path, name);
        free(parent_path);

        if (!slash) break;
        prefix_len = (size_t)(slash - path);
        segment = slash + 1;
    }
}

static int memvfs_build_base_indexes(struct MemvfsDeviceData *devdata) {
    size_t i;
    struct MemvfsBasePathIndexEntry *path_entry;
    size_t bucket;

    devdata->base_path_bucket_count = memvfs_bucket_count(devdata->base->entry_count);
    devdata->base_dir_bucket_count = memvfs_bucket_count(devdata->base->entry_count);
    devdata->overlay_bucket_count = memvfs_bucket_count(devdata->base->entry_count / 2 + 1);

    devdata->base_path_buckets = calloc(devdata->base_path_bucket_count,
                                        sizeof(*devdata->base_path_buckets));
    devdata->base_dir_buckets = calloc(devdata->base_dir_bucket_count,
                                       sizeof(*devdata->base_dir_buckets));
    devdata->overlay_buckets = calloc(devdata->overlay_bucket_count,
                                      sizeof(*devdata->overlay_buckets));
    if (!devdata->base_path_buckets || !devdata->base_dir_buckets ||
        !devdata->overlay_buckets) {
        return enomem();
    }

    for (i = 0; i < (size_t)devdata->base->entry_count; ++i) {
        const char *path = devdata->base->entries[i].path;
        if (!path) continue;

        path_entry = calloc(1, sizeof(*path_entry));
        if (!path_entry) {
            return enomem();
        }
        path_entry->path = path;
        path_entry->entry_idx = (int)i;
        bucket = (size_t)(memvfs_hash_path(path) & (devdata->base_path_bucket_count - 1));
        path_entry->next = devdata->base_path_buckets[bucket];
        devdata->base_path_buckets[bucket] = path_entry;

        memvfs_base_index_path_components(devdata, path);
    }

    return 0;
}

// Look up an overlay entry by path (NULL if not found).
static struct MemvfsOverlayEntry *
memvfs_overlay_lookup(struct MemvfsDeviceData *devdata, const char *path) {
    size_t bucket;
    struct MemvfsOverlayEntry *entry;

    if (!devdata->overlay_buckets) return NULL;
    bucket = (size_t)(memvfs_hash_path(path) & (devdata->overlay_bucket_count - 1));
    for (entry = devdata->overlay_buckets[bucket]; entry; entry = entry->hash_next) {
        if (strcmp(entry->path, path) == 0) {
            return entry;
        }
    }
    return NULL;
}

// Look up a base entry index by path (-1 if not found).
static int memvfs_base_lookup(struct MemvfsDeviceData *devdata, const char *path) {
    size_t bucket;
    struct MemvfsBasePathIndexEntry *entry;

    if (!devdata->base_path_buckets) return -1;
    bucket = (size_t)(memvfs_hash_path(path) & (devdata->base_path_bucket_count - 1));
    for (entry = devdata->base_path_buckets[bucket]; entry; entry = entry->next) {
        if (strcmp(entry->path, path) == 0) {
            return entry->entry_idx;
        }
    }
    return -1;
}

// Get mode_t for an entry type and permission bits.
static mode_t memvfs_make_mode(int type, uint16_t perms) {
    mode_t m = perms ? perms : 0644;
    switch (type) {
    case FLATVFS_DIR:
        m |= S_IFDIR;
        break;
    case FLATVFS_SYMLINK:
        m |= S_IFLNK;
        break;
    case FLATVFS_FILE:
    default:
        m |= S_IFREG;
        break;
    }
    return m;
}

// Fill stat buffer from a base entry.
static void memvfs_stat_base(const flatvfs_entry_t *e, struct stat *st,
                             u32 dev, u64 ino) {
    memset(st, 0, sizeof(*st));
    st->st_dev = dev;
    st->st_ino = ino ? ino : (ino_t)(uintptr_t)e;
    st->st_mode = memvfs_make_mode(e->type, e->mode);
    st->st_nlink = (e->type == FLATVFS_DIR) ? 2 : 1;
    st->st_uid = 0;
    st->st_gid = 0;
    st->st_size = (e->type == FLATVFS_FILE) ? (off_t)e->data_size : 0;
    if (e->type == FLATVFS_SYMLINK && e->symlink_target)
        st->st_size = (off_t)strlen(e->symlink_target);
    st->st_blksize = 4096;
    st->st_blocks = (st->st_size + 511) / 512;
}

// Fill stat buffer from an overlay entry.
static void memvfs_stat_overlay(struct MemvfsOverlayEntry *e, struct stat *st,
                                u32 dev) {
    memset(st, 0, sizeof(*st));
    st->st_dev = dev;
    st->st_ino = (ino_t)(uintptr_t)e;
    st->st_mode = memvfs_make_mode(e->type, (uint16_t)(e->mode & 0xFFFF));
    st->st_nlink = (e->type == FLATVFS_DIR) ? 2 : 1;
    st->st_uid = 0;
    st->st_gid = 0;
    st->st_size = (e->type == FLATVFS_FILE) ? (off_t)e->data_size : 0;
    if (e->type == FLATVFS_SYMLINK && e->symlink_target)
        st->st_size = (off_t)strlen(e->symlink_target);
    st->st_blksize = 4096;
    st->st_blocks = (st->st_size + 511) / 512;
}

// Create an overlay entry (or get existing) at a given path.
static struct MemvfsOverlayEntry *
memvfs_overlay_create(struct MemvfsDeviceData *devdata, const char *path,
                      int type, mode_t mode) {
    pthread_mutex_lock(&devdata->overlay_lock);
    struct MemvfsOverlayEntry *e = memvfs_overlay_lookup(devdata, path);
    if (e) {
        // Reuse existing
        if (e->type == MEMVFS_DELETED) {
            e->type = type;
            e->mode = mode;
        }
        pthread_mutex_unlock(&devdata->overlay_lock);
        return e;
    }
    e = calloc(1, sizeof(*e));
    if (!e) {
        pthread_mutex_unlock(&devdata->overlay_lock);
        return NULL;
    }
    e->path = strdup(path);
    if (!e->path) {
        free(e);
        pthread_mutex_unlock(&devdata->overlay_lock);
        return NULL;
    }
    e->type = type;
    e->mode = mode;
    e->hash_next =
        devdata->overlay_buckets[memvfs_hash_path(path) & (devdata->overlay_bucket_count - 1)];
    devdata->overlay_buckets[memvfs_hash_path(path) & (devdata->overlay_bucket_count - 1)] = e;
    e->next = devdata->overlay;
    devdata->overlay = e;
    pthread_mutex_unlock(&devdata->overlay_lock);
    return e;
}

// Allocate a VfsInfo with MemvfsFileData for a given entry.
static int memvfs_create_info(struct VfsDevice *dev, struct VfsInfo *parent,
                              const char *name, int entry_idx,
                              struct MemvfsOverlayEntry *ov, u32 mode,
                              struct VfsInfo **out) {
    struct VfsInfo *info;
    struct MemvfsFileData *fdata;
    char *copyname;
    int rc = VfsCreateInfo(&info);
    if (rc) return rc;

    fdata = calloc(1, sizeof(*fdata));
    if (!fdata) {
        unassert(!VfsFreeInfo(info));
        return enomem();
    }

    copyname = name ? strdup(name) : strdup("");
    if (!copyname) {
        free(fdata);
        unassert(!VfsFreeInfo(info));
        return enomem();
    }

    if (VfsAcquireDevice(dev, &info->device) == -1) {
        free(copyname);
        free(fdata);
        unassert(!VfsFreeInfo(info));
        return -1;
    }

    if (VfsAcquireInfo(parent, &info->parent) == -1) {
        free(copyname);
        free(fdata);
        unassert(!VfsFreeInfo(info));
        return -1;
    }

    fdata->entry_idx = entry_idx;
    fdata->overlay_entry = ov;
    fdata->read_offset = 0;
    fdata->flags = 0;

    info->name = copyname;
    info->namelen = strlen(copyname);
    info->data = fdata;
    info->mode = mode;
    info->dev = dev->dev;

    // Use a unique inode number
    if (ov)
        info->ino = (u64)(uintptr_t)ov;
    else if (entry_idx >= 0)
        info->ino = (u64)(entry_idx + 1);
    else
        info->ino = 1; // root

    *out = info;
    return 0;
}

// Get the basename from a path (pointer into the string, not a copy).
static const char *memvfs_basename(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

// Check if 'child_path' is a direct child of 'dir_path'.
// dir_path="" means root (children are entries with no '/' in path).
// dir_path="bin" means children are "bin/X" where X has no '/'.
static int memvfs_is_direct_child(const char *dir_path, size_t dir_len,
                                  const char *child_path) {
    if (dir_len == 0) {
        // Root dir — direct child has no '/' in path
        return (strchr(child_path, '/') == NULL);
    }
    // child must start with dir_path + "/"
    if (strncmp(child_path, dir_path, dir_len) != 0) return 0;
    if (child_path[dir_len] != '/') return 0;
    // Remaining part after dir_path/ must have no more '/'
    const char *rest = child_path + dir_len + 1;
    return (rest[0] != '\0' && strchr(rest, '/') == NULL);
}

// Add a child name to a DirData's children list (avoiding duplicates).
static void memvfs_dir_add_child(struct MemvfsDirData *dd, const char *name) {
    // Check for duplicate
    for (int i = 0; i < dd->children_count; i++) {
        if (strcmp(dd->children[i], name) == 0) return;
    }
    if (dd->children_count >= dd->children_capacity) {
        int newcap = dd->children_capacity ? dd->children_capacity * 2 : 64;
        char **newlist = realloc(dd->children, sizeof(char *) * newcap);
        if (!newlist) return;
        dd->children = newlist;
        dd->children_capacity = newcap;
    }
    dd->children[dd->children_count++] = strdup(name);
}

static int memvfs_error(int code) {
    errno = code;
    return -1;
}

static ssize_t memvfs_error_ssize(int code) {
    errno = code;
    return -1;
}

static off_t memvfs_error_off(int code) {
    errno = code;
    return -1;
}

static int memvfs_file_view(struct VfsInfo *info, const uint8_t **data,
                            size_t *data_size) {
    struct MemvfsFileData *fdata;
    struct MemvfsDeviceData *devdata;

    if (!info || !info->data || !data || !data_size) return efault();

    fdata = (struct MemvfsFileData *)info->data;
    devdata = (struct MemvfsDeviceData *)info->device->data;

    if (fdata->overlay_entry) {
        if (fdata->overlay_entry->type != FLATVFS_FILE) return eisdir();
        *data = fdata->overlay_entry->data;
        *data_size = fdata->overlay_entry->data_size;
        return 0;
    }
    if (fdata->entry_idx >= 0 && fdata->entry_idx < devdata->base->entry_count) {
        const flatvfs_entry_t *entry = &devdata->base->entries[fdata->entry_idx];
        if (entry->type != FLATVFS_FILE) return eisdir();
        *data = entry->data;
        *data_size = entry->data_size;
        return 0;
    }

    return eisdir();
}

// ── VfsOps implementation ───────────────────────────────────────────────────

static int MemvfsInit(const char *source, u64 flags, const void *data,
                      struct VfsDevice **out_device,
                      struct VfsMount **out_mount) {
    (void)source;
    (void)flags;

    // 'data' is a pointer to const flatvfs_t *
    const flatvfs_t *base = (const flatvfs_t *)data;
    if (!base) return einval();

    struct VfsDevice *dev;
    int rc = VfsCreateDevice(&dev);
    if (rc) return rc;

    struct MemvfsDeviceData *devdata = calloc(1, sizeof(*devdata));
    if (!devdata) {
        unassert(!VfsFreeDevice(dev));
        return enomem();
    }
    devdata->base = base;
    devdata->overlay = NULL;
    pthread_mutex_init(&devdata->overlay_lock, NULL);
    rc = memvfs_build_base_indexes(devdata);
    if (rc) {
        pthread_mutex_destroy(&devdata->overlay_lock);
        free(devdata);
        unassert(!VfsFreeDevice(dev));
        return rc;
    }

    dev->data = devdata;
    dev->ops = &g_omni_memfs.ops;

    // Create root VfsInfo
    struct VfsInfo *root;
    rc = memvfs_create_info(dev, NULL, "", -1, NULL, S_IFDIR | 0755, &root);
    if (rc) {
        unassert(!VfsFreeDevice(dev));
        return rc;
    }
    dev->root = root;

    *out_device = dev;

    // Create mount at root
    if (out_mount) {
        // VfsMount allocation — blink expects us to allocate it
        struct VfsMount *mnt = calloc(1, sizeof(*mnt));
        if (!mnt) {
            unassert(!VfsFreeInfo(root));
            return enomem();
        }
        mnt->root = root;
        mnt->baseino = 0;
        dll_init(&mnt->elem);
        *out_mount = mnt;
    }

    return 0;
}

static int MemvfsFreeinfo(void *data) {
    if (!data) return 0;
    struct MemvfsFileData *fdata = (struct MemvfsFileData *)data;
    // Don't free overlay_entry — it belongs to the device overlay list
    free(fdata);
    return 0;
}

static int MemvfsFreedevice(void *data) {
    size_t i;
    if (!data) return 0;
    struct MemvfsDeviceData *devdata = (struct MemvfsDeviceData *)data;
    // Free overlay entries
    struct MemvfsOverlayEntry *e = devdata->overlay;
    while (e) {
        struct MemvfsOverlayEntry *next = e->next;
        free(e->path);
        free(e->data);
        free(e->symlink_target);
        free(e);
        e = next;
    }
    if (devdata->base_path_buckets) {
        for (i = 0; i < devdata->base_path_bucket_count; ++i) {
            struct MemvfsBasePathIndexEntry *entry = devdata->base_path_buckets[i];
            while (entry) {
                struct MemvfsBasePathIndexEntry *next = entry->next;
                free(entry);
                entry = next;
            }
        }
        free(devdata->base_path_buckets);
    }
    if (devdata->base_dir_buckets) {
        for (i = 0; i < devdata->base_dir_bucket_count; ++i) {
            struct MemvfsBaseDirIndexEntry *entry = devdata->base_dir_buckets[i];
            while (entry) {
                struct MemvfsBaseDirIndexEntry *next = entry->next;
                struct MemvfsBaseDirChild *child = entry->children;
                while (child) {
                    struct MemvfsBaseDirChild *child_next = child->next;
                    free(child->name);
                    free(child);
                    child = child_next;
                }
                free(entry->path);
                free(entry);
                entry = next;
            }
        }
        free(devdata->base_dir_buckets);
    }
    free(devdata->overlay_buckets);
    pthread_mutex_destroy(&devdata->overlay_lock);
    free(devdata);
    return 0;
}

static int MemvfsFinddir(struct VfsInfo *parent, const char *name,
                         struct VfsInfo **out) {
    if (!parent || !name || !out) return efault();
    if (name[0] == '\0') return enoent();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)parent->device->data;
    char *fullpath = memvfs_build_path(parent, name);
    if (!fullpath) return enomem();

    if (fullpath[0] == '\0') {
        int rc = memvfs_create_info(parent->device, NULL, "", -1, NULL,
                                    S_IFDIR | 0755, out);
        free(fullpath);
        return rc;
    }

    // Check overlay first (including deleted markers)
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov) {
        if (ov->type == MEMVFS_DELETED) {
            free(fullpath);
            return enoent();
        }
        int rc = memvfs_create_info(parent->device, parent, name, -2, ov,
                                    memvfs_make_mode(ov->type,
                                                     (uint16_t)(ov->mode & 0xFFFF)),
                                    out);
        free(fullpath);
        return rc;
    }

    // Check base
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        const flatvfs_entry_t *e = &devdata->base->entries[idx];
        int rc = memvfs_create_info(parent->device, parent, name, idx, NULL,
                                    memvfs_make_mode(e->type, e->mode), out);
        free(fullpath);
        return rc;
    }

    // Not found as exact match — check if it's an implicit directory.
    if (memvfs_base_dir_lookup(devdata, fullpath)) {
        int rc = memvfs_create_info(parent->device, parent, name, -1, NULL,
                                    S_IFDIR | 0755, out);
        struct MemvfsOverlayEntry *synth =
            memvfs_overlay_create(devdata, fullpath, FLATVFS_DIR, 0755);
        if (synth && *out) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->entry_idx = -2;
            fdata->overlay_entry = synth;
        }
        free(fullpath);
        return rc;
    }

    free(fullpath);
    return enoent();
}

static int MemvfsTraverse(struct VfsInfo **dir, const char **path,
                          struct VfsInfo *root) {
    // Handle ".." by walking up parent pointers
    if (!dir || !*dir || !path || !*path) return efault();

    while (**path == '/') (*path)++;

    if ((*path)[0] == '.' && (*path)[1] == '.' &&
        ((*path)[2] == '/' || (*path)[2] == '\0')) {
        struct VfsInfo *parent = (*dir)->parent;
        if (!parent) parent = root ? root : *dir;

        struct VfsInfo *acquired;
        int rc = VfsAcquireInfo(parent, &acquired);
        if (rc) return rc;

        VfsFreeInfo(*dir);
        *dir = acquired;

        *path += 2;
        if (**path == '/') (*path)++;
        return 0;
    }

    if ((*path)[0] == '.' && ((*path)[1] == '/' || (*path)[1] == '\0')) {
        *path += 1;
        if (**path == '/') (*path)++;
        return 0;
    }

    return 0;
}

static ssize_t MemvfsReadlink(struct VfsInfo *info, char **out) {
    if (!info || !info->data || !out) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;

    const char *target = NULL;

    if (fdata->overlay_entry) {
        if (fdata->overlay_entry->type != FLATVFS_SYMLINK) return einval();
        target = fdata->overlay_entry->symlink_target;
    } else if (fdata->entry_idx >= 0 &&
               fdata->entry_idx < devdata->base->entry_count) {
        const flatvfs_entry_t *e = &devdata->base->entries[fdata->entry_idx];
        if (e->type != FLATVFS_SYMLINK) return einval();
        target = e->symlink_target;
    }

    if (!target) return einval();

    *out = strdup(target);
    if (!*out) return enomem();
    return (ssize_t)strlen(target);
}

static int MemvfsMkdir(struct VfsInfo *parent, const char *name, mode_t mode) {
    if (!parent || !name) return efault();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)parent->device->data;
    char *fullpath = memvfs_build_path(parent, name);
    if (!fullpath) return enomem();

    // Check if already exists
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov && ov->type != MEMVFS_DELETED) {
        free(fullpath);
        return eexist();
    }
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        free(fullpath);
        return eexist();
    }

    // Create overlay directory
    struct MemvfsOverlayEntry *entry =
        memvfs_overlay_create(devdata, fullpath, FLATVFS_DIR,
                              mode ? mode : 0755);
    free(fullpath);
    return entry ? 0 : enomem();
}

static int MemvfsOpen(struct VfsInfo *dir, const char *name, int flags,
                      int mode, struct VfsInfo **out) {
    if (!dir || !out) return efault();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)dir->device->data;

    // If name is NULL or empty, we're opening the directory itself
    if (!name || name[0] == '\0') {
        struct MemvfsFileData *pdata = (struct MemvfsFileData *)dir->data;
        if (!pdata) return efault();
        int rc = memvfs_create_info(dir->device, dir->parent,
                                    dir->name ? dir->name : "",
                                    pdata->entry_idx, pdata->overlay_entry,
                                    dir->mode, out);
        if (!rc) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->flags = flags;
        }
        return rc;
    }

    char *fullpath = memvfs_build_path(dir, name);
    if (!fullpath) return enomem();

    if (fullpath[0] == '\0') {
        int rc = memvfs_create_info(dir->device, NULL, "", -1, NULL,
                                    S_IFDIR | 0755, out);
        if (!rc) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->flags = flags;
        }
        free(fullpath);
        return rc;
    }

    // Check overlay first
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov && ov->type == MEMVFS_DELETED) {
        // File was deleted — if O_CREAT, recreate
        if (flags & O_CREAT) {
            ov->type = FLATVFS_FILE;
            ov->mode = mode ? (mode_t)mode : 0644;
            free(ov->data);
            ov->data = NULL;
            ov->data_size = 0;
            ov->data_capacity = 0;
            int rc = memvfs_create_info(
                dir->device, dir, name, -2, ov,
                memvfs_make_mode(FLATVFS_FILE, (uint16_t)(ov->mode & 0xFFFF)),
                out);
            if (!rc) {
                struct MemvfsFileData *fdata =
                    (struct MemvfsFileData *)(*out)->data;
                fdata->flags = flags;
            }
            free(fullpath);
            return rc;
        }
        free(fullpath);
        return enoent();
    }

    if (ov) {
        int rc = memvfs_create_info(
            dir->device, dir, name, -2, ov,
            memvfs_make_mode(ov->type, (uint16_t)(ov->mode & 0xFFFF)), out);
        if (!rc) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->flags = flags;
            if ((flags & O_TRUNC) && ov->type == FLATVFS_FILE) {
                free(ov->data);
                ov->data = NULL;
                ov->data_size = 0;
                ov->data_capacity = 0;
            }
        }
        free(fullpath);
        return rc;
    }

    // Check base
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        const flatvfs_entry_t *e = &devdata->base->entries[idx];

        // O_TRUNC must materialize an empty overlay immediately.
        if (flags & O_TRUNC) {
            struct MemvfsOverlayEntry *cow =
                memvfs_overlay_create(devdata, fullpath, e->type,
                                      e->mode ? e->mode : 0644);
            if (!cow) {
                free(fullpath);
                return enomem();
            }
            free(cow->data);
            cow->data = NULL;
            cow->data_size = 0;
            cow->data_capacity = 0;
            int rc = memvfs_create_info(
                dir->device, dir, name, -2, cow,
                memvfs_make_mode(cow->type,
                                 (uint16_t)(cow->mode & 0xFFFF)),
                out);
            if (!rc) {
                struct MemvfsFileData *fdata =
                    (struct MemvfsFileData *)(*out)->data;
                fdata->flags = flags;
                if (flags & O_APPEND)
                    fdata->read_offset = cow->data_size;
            }
            free(fullpath);
            return rc;
        }

        // For writable opens, defer copy-on-write until the first mutation.
        if ((flags & O_WRONLY) || (flags & O_RDWR)) {
            int rc = memvfs_create_info(dir->device, dir, name, idx, NULL,
                                        memvfs_make_mode(e->type, e->mode), out);
            if (!rc) {
                struct MemvfsFileData *fdata =
                    (struct MemvfsFileData *)(*out)->data;
                fdata->flags = flags;
                if ((flags & O_APPEND) && e->type == FLATVFS_FILE) {
                    fdata->read_offset = e->data_size;
                }
            }
            free(fullpath);
            return rc;
        }

        int rc = memvfs_create_info(dir->device, dir, name, idx, NULL,
                                    memvfs_make_mode(e->type, e->mode), out);
        if (!rc) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->flags = flags;
        }
        free(fullpath);
        return rc;
    }

    // Not found — create if O_CREAT
    if (flags & O_CREAT) {
        struct MemvfsOverlayEntry *entry = memvfs_overlay_create(
            devdata, fullpath, FLATVFS_FILE, mode ? (mode_t)mode : 0644);
        if (!entry) {
            free(fullpath);
            return enomem();
        }
        int rc = memvfs_create_info(
            dir->device, dir, name, -2, entry,
            memvfs_make_mode(FLATVFS_FILE,
                             (uint16_t)(entry->mode & 0xFFFF)),
            out);
        if (!rc) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->flags = flags;
        }
        free(fullpath);
        return rc;
    }

    // Also check for implicit directories (paths that exist as prefixes).
    if (memvfs_base_dir_lookup(devdata, fullpath)) {
        struct MemvfsOverlayEntry *synth =
            memvfs_overlay_create(devdata, fullpath, FLATVFS_DIR, 0755);
        int rc = memvfs_create_info(dir->device, dir, name, -2, synth,
                                    S_IFDIR | 0755, out);
        if (!rc) {
            struct MemvfsFileData *fdata =
                (struct MemvfsFileData *)(*out)->data;
            fdata->flags = flags;
        }
        free(fullpath);
        return rc;
    }

    free(fullpath);
    return enoent();
}

static int MemvfsAccess(struct VfsInfo *dir, const char *name, mode_t amode,
                        int flags) {
    if (!dir) return efault();
    (void)flags;

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)dir->device->data;

    // If no name, check the dir itself
    if (!name || name[0] == '\0') {
        // Dir exists
        return (amode == F_OK) ? 0 : 0;
    }

    char *fullpath = memvfs_build_path(dir, name);
    if (!fullpath) return enomem();

    if (fullpath[0] == '\0') {
        free(fullpath);
        return 0;
    }

    // Check overlay
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov) {
        free(fullpath);
        if (ov->type == MEMVFS_DELETED) return enoent();
        return 0;
    }

    // Check base
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        free(fullpath);
        return 0;
    }

    // Check implicit dirs.
    if (memvfs_base_dir_lookup(devdata, fullpath)) {
        free(fullpath);
        return 0;
    }

    free(fullpath);
    return enoent();
}

static int MemvfsStat(struct VfsInfo *dir, const char *name, struct stat *st,
                      int flags) {
    if (!dir || !st) return efault();
    (void)flags;

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)dir->device->data;

    char *fullpath;
    if (!name || name[0] == '\0') {
        // Stat the directory itself
        fullpath = strdup(memvfs_get_path(dir));
    } else {
        fullpath = memvfs_build_path(dir, name);
    }
    if (!fullpath) return enomem();

    // Root directory
    if (fullpath[0] == '\0') {
        memset(st, 0, sizeof(*st));
        st->st_dev = dir->dev;
        st->st_ino = 1;
        st->st_mode = S_IFDIR | 0755;
        st->st_nlink = 2;
        st->st_blksize = 4096;
        free(fullpath);
        return 0;
    }

    // Check overlay
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov) {
        if (ov->type == MEMVFS_DELETED) {
            free(fullpath);
            return enoent();
        }
        memvfs_stat_overlay(ov, st, dir->dev);
        free(fullpath);
        return 0;
    }

    // Check base
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        memvfs_stat_base(&devdata->base->entries[idx], st, dir->dev,
                         (u64)(idx + 1));
        free(fullpath);
        return 0;
    }

    // Check implicit dirs.
    if (memvfs_base_dir_lookup(devdata, fullpath)) {
        memset(st, 0, sizeof(*st));
        st->st_dev = dir->dev;
        st->st_ino = (ino_t)(uintptr_t)fullpath;
        st->st_mode = S_IFDIR | 0755;
        st->st_nlink = 2;
        st->st_blksize = 4096;
        free(fullpath);
        return 0;
    }

    free(fullpath);
    return enoent();
}

static int MemvfsFstat(struct VfsInfo *info, struct stat *st) {
    if (!info || !st) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;

    if (!fdata) return efault();

    if (fdata->entry_idx == -1) {
        // Root
        memset(st, 0, sizeof(*st));
        st->st_dev = info->dev;
        st->st_ino = 1;
        st->st_mode = S_IFDIR | 0755;
        st->st_nlink = 2;
        st->st_blksize = 4096;
        return 0;
    }

    if (fdata->overlay_entry) {
        if (fdata->overlay_entry->type == MEMVFS_DELETED) return enoent();
        memvfs_stat_overlay(fdata->overlay_entry, st, info->dev);
        return 0;
    }

    if (fdata->entry_idx >= 0 &&
        fdata->entry_idx < devdata->base->entry_count) {
        memvfs_stat_base(&devdata->base->entries[fdata->entry_idx], st,
                         info->dev, info->ino);
        return 0;
    }

    return enoent();
}

static int MemvfsChmod(struct VfsInfo *dir, const char *name, mode_t mode,
                       int flags) {
    (void)flags;
    if (!dir) return efault();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)dir->device->data;
    char *fullpath = memvfs_build_path(dir, name);
    if (!fullpath) return enomem();

    // Check overlay
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov && ov->type != MEMVFS_DELETED) {
        ov->mode = mode;
        free(fullpath);
        return 0;
    }

    // Check base — COW
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        const flatvfs_entry_t *e = &devdata->base->entries[idx];
        struct MemvfsOverlayEntry *cow =
            memvfs_overlay_create(devdata, fullpath, e->type, mode);
        if (!cow) {
            free(fullpath);
            return enomem();
        }
        if (e->type == FLATVFS_FILE && e->data && e->data_size > 0 &&
            !cow->data) {
            cow->data = malloc(e->data_size);
            if (cow->data) {
                memcpy(cow->data, e->data, e->data_size);
                cow->data_size = e->data_size;
                cow->data_capacity = e->data_size;
            }
        }
        if (e->type == FLATVFS_SYMLINK && e->symlink_target &&
            !cow->symlink_target) {
            cow->symlink_target = strdup(e->symlink_target);
        }
        free(fullpath);
        return 0;
    }

    free(fullpath);
    return enoent();
}

static int MemvfsFchmod(struct VfsInfo *info, mode_t mode) {
    if (!info || !info->data) return efault();
    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    if (fdata->overlay_entry) {
        fdata->overlay_entry->mode = mode;
        return 0;
    }
    // For base entries, COW
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;
    if (fdata->entry_idx >= 0 &&
        fdata->entry_idx < devdata->base->entry_count) {
        const flatvfs_entry_t *e = &devdata->base->entries[fdata->entry_idx];
        struct MemvfsOverlayEntry *cow = memvfs_overlay_create(
            devdata, e->path, e->type, mode);
        if (!cow) return enomem();
        if (e->type == FLATVFS_FILE && e->data && e->data_size > 0 &&
            !cow->data) {
            cow->data = malloc(e->data_size);
            if (cow->data) {
                memcpy(cow->data, e->data, e->data_size);
                cow->data_size = e->data_size;
                cow->data_capacity = e->data_size;
            }
        }
        fdata->overlay_entry = cow;
        fdata->entry_idx = -2;
        return 0;
    }
    return enoent();
}

static int MemvfsChown(struct VfsInfo *dir, const char *name, uid_t uid,
                       gid_t gid, int flags) {
    (void)dir;
    (void)name;
    (void)uid;
    (void)gid;
    (void)flags;
    return 0; // Silently succeed — we're running as root
}

static int MemvfsFchown(struct VfsInfo *info, uid_t uid, gid_t gid) {
    (void)info;
    (void)uid;
    (void)gid;
    return 0;
}

static int MemvfsFtruncate(struct VfsInfo *info, off_t length) {
    if (!info || !info->data) return efault();
    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;

    // Must have an overlay entry for writing
    if (!fdata->overlay_entry) {
        // COW
        struct MemvfsDeviceData *devdata =
            (struct MemvfsDeviceData *)info->device->data;
        if (fdata->entry_idx >= 0 &&
            fdata->entry_idx < devdata->base->entry_count) {
            const flatvfs_entry_t *e =
                &devdata->base->entries[fdata->entry_idx];
            struct MemvfsOverlayEntry *cow = memvfs_overlay_create(
                devdata, e->path, e->type, e->mode ? e->mode : 0644);
            if (!cow) return enomem();
            if (e->data && e->data_size > 0) {
                cow->data = malloc(e->data_size);
                if (cow->data) {
                    memcpy(cow->data, e->data, e->data_size);
                    cow->data_size = e->data_size;
                    cow->data_capacity = e->data_size;
                }
            }
            fdata->overlay_entry = cow;
            fdata->entry_idx = -2;
        } else {
            return einval();
        }
    }

    struct MemvfsOverlayEntry *ov = fdata->overlay_entry;
    if ((size_t)length > ov->data_capacity) {
        uint8_t *newdata = realloc(ov->data, (size_t)length);
        if (!newdata) return enomem();
        memset(newdata + ov->data_size, 0, (size_t)length - ov->data_size);
        ov->data = newdata;
        ov->data_capacity = (size_t)length;
    }
    ov->data_size = (size_t)length;
    if (fdata->read_offset > (size_t)length) fdata->read_offset = (size_t)length;
    return 0;
}

static int MemvfsClose(struct VfsInfo *info) {
    // Nothing special to do — Freeinfo handles cleanup
    (void)info;
    return 0;
}

static int MemvfsLink(struct VfsInfo *olddir, const char *oldname,
                      struct VfsInfo *newdir, const char *newname, int flags) {
    (void)olddir;
    (void)oldname;
    (void)newdir;
    (void)newname;
    (void)flags;
    return eperm(); // Hard links not supported
}

static int MemvfsUnlink(struct VfsInfo *dir, const char *name, int flags) {
    if (!dir || !name) return efault();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)dir->device->data;
    char *fullpath = memvfs_build_path(dir, name);
    if (!fullpath) return enomem();

    // If AT_REMOVEDIR, this is rmdir
    int is_rmdir = (flags & AT_REMOVEDIR);

    // Check overlay
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, fullpath);
    if (ov && ov->type != MEMVFS_DELETED) {
        if (is_rmdir && ov->type != FLATVFS_DIR) {
            free(fullpath);
            return enotdir();
        }
        if (!is_rmdir && ov->type == FLATVFS_DIR) {
            free(fullpath);
            return eisdir();
        }
        ov->type = MEMVFS_DELETED;
        free(ov->data);
        ov->data = NULL;
        ov->data_size = 0;
        free(fullpath);
        return 0;
    }

    // Check base
    int idx = memvfs_base_lookup(devdata, fullpath);
    if (idx >= 0) {
        const flatvfs_entry_t *e = &devdata->base->entries[idx];
        if (is_rmdir && e->type != FLATVFS_DIR) {
            free(fullpath);
            return enotdir();
        }
        if (!is_rmdir && e->type == FLATVFS_DIR) {
            free(fullpath);
            return eisdir();
        }
        // Mark as deleted in overlay
        struct MemvfsOverlayEntry *del =
            memvfs_overlay_create(devdata, fullpath, MEMVFS_DELETED, 0);
        free(fullpath);
        return del ? 0 : enomem();
    }

    free(fullpath);
    return enoent();
}

static ssize_t MemvfsRead(struct VfsInfo *info, void *buf, size_t nbyte) {
    if (!info || !info->data || !buf) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;

    const uint8_t *data = NULL;
    size_t data_size = 0;

    if (fdata->overlay_entry) {
        data = fdata->overlay_entry->data;
        data_size = fdata->overlay_entry->data_size;
    } else if (fdata->entry_idx >= 0 &&
               fdata->entry_idx < devdata->base->entry_count) {
        const flatvfs_entry_t *e = &devdata->base->entries[fdata->entry_idx];
        data = e->data;
        data_size = e->data_size;
    } else {
        return eisdir(); // root or dir
    }

    if (fdata->read_offset >= data_size) return 0;

    size_t avail = data_size - fdata->read_offset;
    size_t toread = nbyte < avail ? nbyte : avail;

    if (data && toread > 0)
        memcpy(buf, data + fdata->read_offset, toread);
    fdata->read_offset += toread;
    return (ssize_t)toread;
}

static ssize_t MemvfsWrite(struct VfsInfo *info, const void *buf,
                           size_t nbyte) {
    if (!info || !info->data) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;

    // Must have overlay entry for writing
    if (!fdata->overlay_entry) {
        // Need COW
        struct MemvfsDeviceData *devdata =
            (struct MemvfsDeviceData *)info->device->data;
        if (fdata->entry_idx >= 0 &&
            fdata->entry_idx < devdata->base->entry_count) {
            const flatvfs_entry_t *e =
                &devdata->base->entries[fdata->entry_idx];
            struct MemvfsOverlayEntry *cow = memvfs_overlay_create(
                devdata, e->path, e->type, e->mode ? e->mode : 0644);
            if (!cow) return enomem();
            if (e->data && e->data_size > 0 && !cow->data) {
                cow->data = malloc(e->data_size);
                if (cow->data) {
                    memcpy(cow->data, e->data, e->data_size);
                    cow->data_size = e->data_size;
                    cow->data_capacity = e->data_size;
                }
            }
            fdata->overlay_entry = cow;
            fdata->entry_idx = -2;
        } else {
            return memvfs_error_ssize(EROFS);
        }
    }

    struct MemvfsOverlayEntry *ov = fdata->overlay_entry;
    size_t offset = fdata->read_offset;
    size_t end = offset + nbyte;

    if (end > ov->data_capacity) {
        size_t newcap = ov->data_capacity ? ov->data_capacity : 4096;
        while (newcap < end) newcap *= 2;
        uint8_t *newdata = realloc(ov->data, newcap);
        if (!newdata) return enomem();
        // Zero fill gap
        if (offset > ov->data_size)
            memset(newdata + ov->data_size, 0, offset - ov->data_size);
        ov->data = newdata;
        ov->data_capacity = newcap;
    }

    if (buf && nbyte > 0) memcpy(ov->data + offset, buf, nbyte);
    fdata->read_offset = end;
    if (end > ov->data_size) ov->data_size = end;

    return (ssize_t)nbyte;
}

static ssize_t MemvfsPread(struct VfsInfo *info, void *buf, size_t nbyte,
                           off_t offset) {
    if (!info || !info->data || !buf) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;

    const uint8_t *data = NULL;
    size_t data_size = 0;

    if (fdata->overlay_entry) {
        data = fdata->overlay_entry->data;
        data_size = fdata->overlay_entry->data_size;
    } else if (fdata->entry_idx >= 0 &&
               fdata->entry_idx < devdata->base->entry_count) {
        const flatvfs_entry_t *e = &devdata->base->entries[fdata->entry_idx];
        data = e->data;
        data_size = e->data_size;
    } else {
        return eisdir();
    }

    if ((size_t)offset >= data_size) return 0;

    size_t avail = data_size - (size_t)offset;
    size_t toread = nbyte < avail ? nbyte : avail;

    if (data && toread > 0) memcpy(buf, data + offset, toread);
    return (ssize_t)toread;
}

static ssize_t MemvfsPwrite(struct VfsInfo *info, const void *buf,
                            size_t nbyte, off_t offset) {
    if (!info || !info->data) return efault();

    // Save/restore offset
    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    size_t saved = fdata->read_offset;
    fdata->read_offset = (size_t)offset;
    ssize_t rc = MemvfsWrite(info, buf, nbyte);
    fdata->read_offset = saved;
    return rc;
}

static ssize_t MemvfsReadv(struct VfsInfo *info, const struct iovec *iov,
                           int iovcnt) {
    ssize_t total = 0;
    for (int i = 0; i < iovcnt; i++) {
        ssize_t n = MemvfsRead(info, iov[i].iov_base, iov[i].iov_len);
        if (n < 0) return n;
        total += n;
        if ((size_t)n < iov[i].iov_len) break;
    }
    return total;
}

static ssize_t MemvfsWritev(struct VfsInfo *info, const struct iovec *iov,
                            int iovcnt) {
    ssize_t total = 0;
    for (int i = 0; i < iovcnt; i++) {
        ssize_t n = MemvfsWrite(info, iov[i].iov_base, iov[i].iov_len);
        if (n < 0) return n;
        total += n;
        if ((size_t)n < iov[i].iov_len) break;
    }
    return total;
}

static ssize_t MemvfsPreadv(struct VfsInfo *info, const struct iovec *iov,
                            int iovcnt, off_t offset) {
    ssize_t total = 0;
    for (int i = 0; i < iovcnt; i++) {
        ssize_t n = MemvfsPread(info, iov[i].iov_base, iov[i].iov_len,
                                offset + total);
        if (n < 0) return n;
        total += n;
        if ((size_t)n < iov[i].iov_len) break;
    }
    return total;
}

static ssize_t MemvfsPwritev(struct VfsInfo *info, const struct iovec *iov,
                             int iovcnt, off_t offset) {
    ssize_t total = 0;
    for (int i = 0; i < iovcnt; i++) {
        ssize_t n = MemvfsPwrite(info, iov[i].iov_base, iov[i].iov_len,
                                 offset + total);
        if (n < 0) return n;
        total += n;
        if ((size_t)n < iov[i].iov_len) break;
    }
    return total;
}

static off_t MemvfsSeek(struct VfsInfo *info, off_t offset, int whence) {
    if (!info || !info->data) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;

    size_t file_size = 0;
    if (fdata->overlay_entry) {
        file_size = fdata->overlay_entry->data_size;
    } else if (fdata->entry_idx >= 0 &&
               fdata->entry_idx < devdata->base->entry_count) {
        file_size = devdata->base->entries[fdata->entry_idx].data_size;
    }

    off_t newpos;
    switch (whence) {
    case SEEK_SET:
        newpos = offset;
        break;
    case SEEK_CUR:
        newpos = (off_t)fdata->read_offset + offset;
        break;
    case SEEK_END:
        newpos = (off_t)file_size + offset;
        break;
    default:
        return einval();
    }

    if (newpos < 0) return einval();
    fdata->read_offset = (size_t)newpos;
    return newpos;
}

static int MemvfsFsync(struct VfsInfo *info) {
    (void)info;
    return 0;
}

static int MemvfsFdatasync(struct VfsInfo *info) {
    (void)info;
    return 0;
}

static void *MemvfsMmap(struct VfsInfo *info, void *addr, size_t len, int prot,
                        int flags, off_t offset) {
    const uint8_t *data;
    size_t data_size;
    size_t copy_size = 0;
    int map_prot;
    int map_flags = flags;
    void *mapped;

    if (memvfs_file_view(info, &data, &data_size) == -1) {
        return MAP_FAILED;
    }

    if (offset < 0) {
        einval();
        return MAP_FAILED;
    }

#ifdef MAP_ANONYMOUS
    map_flags |= MAP_ANONYMOUS;
#elif defined(MAP_ANON)
    map_flags |= MAP_ANON;
#endif

    map_prot = prot;
    if (!(map_prot & PROT_READ) || !(map_prot & PROT_WRITE)) {
        map_prot |= PROT_READ | PROT_WRITE;
    }
    map_prot &= ~PROT_EXEC;

    mapped = mmap(addr, len, map_prot, map_flags, -1, 0);
    if (mapped == MAP_FAILED) {
        return MAP_FAILED;
    }

    if ((size_t)offset < data_size) {
        copy_size = data_size - (size_t)offset;
        if (copy_size > len) {
            copy_size = len;
        }
        if (copy_size > 0 && data) {
            memcpy(mapped, data + offset, copy_size);
        }
    }

    if (mprotect(mapped, len, prot) == -1) {
        unassert(!munmap(mapped, len));
        return MAP_FAILED;
    }

    return mapped;
}

static int MemvfsMunmap(struct VfsInfo *info, void *addr, size_t len) {
    (void)info;
    (void)addr;
    (void)len;
    return 0;
}

static int MemvfsMprotect(struct VfsInfo *info, void *addr, size_t len,
                          int prot) {
    (void)info;
    (void)addr;
    (void)len;
    (void)prot;
    return 0;
}

static int MemvfsMsync(struct VfsInfo *info, void *addr, size_t len, int flags) {
    (void)info;
    (void)addr;
    (void)len;
    (void)flags;
    return 0;
}

static int MemvfsFlock(struct VfsInfo *info, int op) {
    (void)info;
    (void)op;
    return 0;
}

static int MemvfsFcntl(struct VfsInfo *info, int cmd, va_list args) {
    (void)args;
    if (!info) return efault();
    switch (cmd) {
    case F_GETFD:
        return 0;
    case F_SETFD:
        return 0;
    case F_GETFL: {
        struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
        return fdata ? fdata->flags : O_RDONLY;
    }
    case F_SETFL:
        return 0;
    default:
        return einval();
    }
}

static int MemvfsIoctl(struct VfsInfo *info, unsigned long request,
                       const void *arg) {
    (void)info;
    (void)request;
    (void)arg;
    return memvfs_error(ENOTTY);
}

static int MemvfsDup(struct VfsInfo *info, struct VfsInfo **out) {
    char *copyname;
    if (!info || !out) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    if (!fdata) return efault();

    struct VfsInfo *dup;
    int rc = VfsCreateInfo(&dup);
    if (rc) return rc;

    struct MemvfsFileData *dup_fdata = calloc(1, sizeof(*dup_fdata));
    if (!dup_fdata) {
        unassert(!VfsFreeInfo(dup));
        return enomem();
    }

    dup_fdata->entry_idx = fdata->entry_idx;
    dup_fdata->read_offset = fdata->read_offset;
    dup_fdata->overlay_entry = fdata->overlay_entry;
    dup_fdata->flags = fdata->flags;

    copyname = info->name ? strdup(info->name) : strdup("");
    if (!copyname) {
        free(dup_fdata);
        unassert(!VfsFreeInfo(dup));
        return enomem();
    }

    if (VfsAcquireDevice(info->device, &dup->device) == -1) {
        free(copyname);
        free(dup_fdata);
        unassert(!VfsFreeInfo(dup));
        return -1;
    }
    if (VfsAcquireInfo(info->parent, &dup->parent) == -1) {
        free(copyname);
        free(dup_fdata);
        unassert(!VfsFreeInfo(dup));
        return -1;
    }

    dup->name = copyname;
    dup->namelen = info->namelen;
    dup->data = dup_fdata;
    dup->mode = info->mode;
    dup->dev = info->dev;
    dup->ino = info->ino;

    *out = dup;
    return 0;
}

static int MemvfsOpendir(struct VfsInfo *info, struct VfsInfo **out) {
    char *copyname;
    if (!info || !out) return efault();

    struct MemvfsFileData *fdata = (struct MemvfsFileData *)info->data;
    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)info->device->data;

    // Get directory path
    const char *dir_path = memvfs_get_path(info);
    size_t dir_len = strlen(dir_path);

    // Build list of direct children
    struct MemvfsDirData *dd = calloc(1, sizeof(*dd));
    if (!dd) return enomem();
    dd->dir_path = strdup(dir_path);
    if (!dd->dir_path) {
        free(dd);
        return enomem();
    }
    if (fdata) {
        dd->file = *fdata;
    } else {
        memset(&dd->file, 0, sizeof(dd->file));
        dd->file.entry_idx = -1;
    }
    dd->dir_path_len = dir_len;
    dd->readdir_pos = 0;
    dd->children = NULL;
    dd->children_count = 0;
    dd->children_capacity = 0;

    // Enumerate indexed base children.
    struct MemvfsBaseDirIndexEntry *dir_index =
        memvfs_base_dir_lookup(devdata, dir_path);
    if (dir_index) {
        for (struct MemvfsBaseDirChild *child = dir_index->children; child;
             child = child->next) {
            char *child_path;
            struct MemvfsOverlayEntry *ov;

            if (dir_len == 0) {
                child_path = strdup(child->name);
            } else {
                child_path = malloc(dir_len + 1 + strlen(child->name) + 1);
                if (!child_path) continue;
                memcpy(child_path, dir_path, dir_len);
                child_path[dir_len] = '/';
                strcpy(child_path + dir_len + 1, child->name);
            }
            ov = memvfs_overlay_lookup(devdata, child_path);
            free(child_path);
            if (ov && ov->type == MEMVFS_DELETED) continue;
            memvfs_dir_add_child(dd, child->name);
        }
    }

    // Scan overlay entries
    for (struct MemvfsOverlayEntry *ov = devdata->overlay; ov; ov = ov->next) {
        if (ov->type == MEMVFS_DELETED) continue;
        if (memvfs_is_direct_child(dir_path, dir_len, ov->path)) {
            const char *basename =
                (dir_len == 0) ? ov->path : ov->path + dir_len + 1;
            memvfs_dir_add_child(dd, basename);
        }
    }

    // Create the VfsInfo for the opened directory
    struct VfsInfo *dirinfo;
    int rc = VfsCreateInfo(&dirinfo);
    if (rc) {
        for (int i = 0; i < dd->children_count; i++) free(dd->children[i]);
        free(dd->children);
        free(dd->dir_path);
        free(dd);
        return rc;
    }

    copyname = info->name ? strdup(info->name) : strdup("");
    if (!copyname) {
        unassert(!VfsFreeInfo(dirinfo));
        for (int i = 0; i < dd->children_count; i++) free(dd->children[i]);
        free(dd->children);
        free(dd->dir_path);
        free(dd);
        return enomem();
    }
    if (VfsAcquireDevice(info->device, &dirinfo->device) == -1) {
        free(copyname);
        unassert(!VfsFreeInfo(dirinfo));
        for (int i = 0; i < dd->children_count; i++) free(dd->children[i]);
        free(dd->children);
        free(dd->dir_path);
        free(dd);
        return -1;
    }
    if (VfsAcquireInfo(info->parent, &dirinfo->parent) == -1) {
        free(copyname);
        unassert(!VfsFreeInfo(dirinfo));
        for (int i = 0; i < dd->children_count; i++) free(dd->children[i]);
        free(dd->children);
        free(dd->dir_path);
        free(dd);
        return -1;
    }
    dirinfo->name = copyname;
    dirinfo->namelen = info->namelen;
    dirinfo->data = dd;
    dirinfo->mode = info->mode;
    dirinfo->dev = info->dev;
    dirinfo->ino = info->ino;

    *out = dirinfo;
    return 0;
}

// Thread-local dirent for Readdir
static _Thread_local struct dirent g_memvfs_dirent;

static struct dirent *MemvfsReaddir(struct VfsInfo *info) {
    if (!info || !info->data) return NULL;

    struct MemvfsDirData *dd = (struct MemvfsDirData *)info->data;
    if (dd->readdir_pos >= dd->children_count) return NULL;

    const char *name = dd->children[dd->readdir_pos++];

    memset(&g_memvfs_dirent, 0, sizeof(g_memvfs_dirent));
    strncpy(g_memvfs_dirent.d_name, name, sizeof(g_memvfs_dirent.d_name) - 1);
    g_memvfs_dirent.d_type = DT_UNKNOWN; // Simplification — caller will stat

    return &g_memvfs_dirent;
}

#ifdef HAVE_SEEKDIR
static void MemvfsSeekdir(struct VfsInfo *info, long offset) {
    if (!info || !info->data) return;
    struct MemvfsDirData *dd = (struct MemvfsDirData *)info->data;
    if (offset < 0) {
        dd->readdir_pos = 0;
    } else if (offset > dd->children_count) {
        dd->readdir_pos = dd->children_count;
    } else {
        dd->readdir_pos = (int)offset;
    }
}

static long MemvfsTelldir(struct VfsInfo *info) {
    if (!info || !info->data) {
        return memvfs_error_off(EFAULT);
    }
    struct MemvfsDirData *dd = (struct MemvfsDirData *)info->data;
    return dd->readdir_pos;
}
#endif

static void MemvfsRewinddir(struct VfsInfo *info) {
    if (!info || !info->data) return;
    struct MemvfsDirData *dd = (struct MemvfsDirData *)info->data;
    dd->readdir_pos = 0;
}

static int MemvfsClosedir(struct VfsInfo *info) {
    if (!info || !info->data) return 0;
    struct MemvfsDirData *dd = (struct MemvfsDirData *)info->data;
    for (int i = 0; i < dd->children_count; i++) free(dd->children[i]);
    free(dd->children);
    free(dd->dir_path);
    free(dd);
    info->data = NULL;
    return 0;
}

static int MemvfsRename(struct VfsInfo *olddir, const char *oldname,
                        struct VfsInfo *newdir, const char *newname) {
    if (!olddir || !oldname || !newdir || !newname) return efault();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)olddir->device->data;

    char *oldpath = memvfs_build_path(olddir, oldname);
    char *newpath = memvfs_build_path(newdir, newname);
    if (!oldpath || !newpath) {
        free(oldpath);
        free(newpath);
        return enomem();
    }

    // Find the source entry (overlay or base)
    struct MemvfsOverlayEntry *ov = memvfs_overlay_lookup(devdata, oldpath);
    int base_idx = memvfs_base_lookup(devdata, oldpath);

    if (!ov && base_idx < 0) {
        free(oldpath);
        free(newpath);
        return enoent();
    }

    if (ov && ov->type != MEMVFS_DELETED) {
        // Create new overlay at newpath
        struct MemvfsOverlayEntry *newov =
            memvfs_overlay_create(devdata, newpath, ov->type, ov->mode);
        if (!newov) {
            free(oldpath);
            free(newpath);
            return enomem();
        }
        newov->data = ov->data;
        newov->data_size = ov->data_size;
        newov->data_capacity = ov->data_capacity;
        newov->symlink_target = ov->symlink_target;
        ov->data = NULL;
        ov->data_size = 0;
        ov->data_capacity = 0;
        ov->symlink_target = NULL;
        ov->type = MEMVFS_DELETED;
    } else if (base_idx >= 0) {
        const flatvfs_entry_t *e = &devdata->base->entries[base_idx];
        struct MemvfsOverlayEntry *newov = memvfs_overlay_create(
            devdata, newpath, e->type, e->mode ? e->mode : 0644);
        if (!newov) {
            free(oldpath);
            free(newpath);
            return enomem();
        }
        if (e->type == FLATVFS_FILE && e->data && e->data_size > 0) {
            newov->data = malloc(e->data_size);
            if (newov->data) {
                memcpy(newov->data, e->data, e->data_size);
                newov->data_size = e->data_size;
                newov->data_capacity = e->data_size;
            }
        }
        if (e->type == FLATVFS_SYMLINK && e->symlink_target)
            newov->symlink_target = strdup(e->symlink_target);
        // Mark old as deleted
        memvfs_overlay_create(devdata, oldpath, MEMVFS_DELETED, 0);
    }

    free(oldpath);
    free(newpath);
    return 0;
}

static int MemvfsUtime(struct VfsInfo *dir, const char *name,
                       const struct timespec ts[2], int flags) {
    (void)dir;
    (void)name;
    (void)ts;
    (void)flags;
    return 0; // Silently succeed
}

static int MemvfsFutime(struct VfsInfo *info, const struct timespec ts[2]) {
    (void)info;
    (void)ts;
    return 0;
}

static int MemvfsSymlink(const char *target, struct VfsInfo *dir,
                         const char *name) {
    if (!target || !dir || !name) return efault();

    struct MemvfsDeviceData *devdata =
        (struct MemvfsDeviceData *)dir->device->data;
    char *fullpath = memvfs_build_path(dir, name);
    if (!fullpath) return enomem();

    struct MemvfsOverlayEntry *entry =
        memvfs_overlay_create(devdata, fullpath, FLATVFS_SYMLINK, 0777);
    if (!entry) {
        free(fullpath);
        return enomem();
    }
    free(entry->symlink_target);
    entry->symlink_target = strdup(target);
    free(fullpath);
    return 0;
}

// ── OmniVfsInit — mount the flatvfs directly at / via blink's VFS layer ────
int OmniVfsInit(const flatvfs_t *vfs) {
    if (!vfs) return -1;
    if (VfsRegister(&g_omni_memfs) == -1) {
        return -1;
    }
    if (VfsInitRootMount("", "memfs", 0, vfs, false, "/") == -1) {
        return -1;
    }
    return 0;
}
