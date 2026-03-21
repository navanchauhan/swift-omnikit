#include "omni_fdfs.h"

#include <fcntl.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "blink/assert.h"
#include "blink/errno.h"
#include "blink/log.h"
#include "blink/thread.h"
#include "blink/vfs.h"

enum OmniFdInfoType {
  OMNI_FD_ROOT_DIR,
  OMNI_FD_ROOT_LINK,
  OMNI_FD_ENTRY,
};

struct OmniFdMountConfig {
  enum OmniFdInfoType root_type;
  const char *link_target;
};

struct OmniFdOpenDir {
  pthread_mutex_t_ lock;
  long index;
  int cursor_fd;
};

struct OmniFdInfo {
  enum OmniFdInfoType type;
  int guest_fd;
  const char *link_target;
  struct OmniFdOpenDir *opendir;
};

static int OmniFdInit(const char *, u64, const void *, struct VfsDevice **,
                      struct VfsMount **);
static int OmniFdFreeinfo(void *);
static int OmniFdFreedevice(void *);
static int OmniFdReadmountentry(struct VfsDevice *, char **, char **, char **);
static int OmniFdFinddir(struct VfsInfo *, const char *, struct VfsInfo **);
static ssize_t OmniFdReadlink(struct VfsInfo *, char **);
static int OmniFdOpen(struct VfsInfo *, const char *, int, int,
                      struct VfsInfo **);
static int OmniFdAccess(struct VfsInfo *, const char *, mode_t, int);
static int OmniFdStat(struct VfsInfo *, const char *, struct stat *, int);
static int OmniFdFstat(struct VfsInfo *, struct stat *);
static int OmniFdClose(struct VfsInfo *);
static int OmniFdDup(struct VfsInfo *, struct VfsInfo **);
static int OmniFdOpendir(struct VfsInfo *, struct VfsInfo **);
static void OmniFdSeekdir(struct VfsInfo *, long);
static long OmniFdTelldir(struct VfsInfo *);
static struct dirent *OmniFdReaddir(struct VfsInfo *);
static void OmniFdRewinddir(struct VfsInfo *);
static int OmniFdClosedir(struct VfsInfo *);

struct VfsSystem g_omni_fdfs = {
    .name = "omni-fd",
    .nodev = true,
    .ops =
        {
            .Init = OmniFdInit,
            .Freeinfo = OmniFdFreeinfo,
            .Freedevice = OmniFdFreedevice,
            .Readmountentry = OmniFdReadmountentry,
            .Finddir = OmniFdFinddir,
            .Readlink = OmniFdReadlink,
            .Open = OmniFdOpen,
            .Access = OmniFdAccess,
            .Stat = OmniFdStat,
            .Fstat = OmniFdFstat,
            .Close = OmniFdClose,
            .Dup = OmniFdDup,
            .Opendir = OmniFdOpendir,
#ifdef HAVE_SEEKDIR
            .Seekdir = OmniFdSeekdir,
            .Telldir = OmniFdTelldir,
#endif
            .Readdir = OmniFdReaddir,
            .Rewinddir = OmniFdRewinddir,
            .Closedir = OmniFdClosedir,
        },
};

static const struct OmniFdMountConfig kOmniFdDirMount = {
    .root_type = OMNI_FD_ROOT_DIR,
    .link_target = NULL,
};

static const struct OmniFdMountConfig kOmniFdDevLinkMount = {
    .root_type = OMNI_FD_ROOT_LINK,
    .link_target = "/proc/self/fd",
};

static mode_t OmniFdMode(enum OmniFdInfoType type) {
  switch (type) {
    case OMNI_FD_ROOT_DIR:
      return S_IFDIR | 0555;
    case OMNI_FD_ROOT_LINK:
      return S_IFLNK | 0777;
    case OMNI_FD_ENTRY:
      return S_IFCHR | 0666;
  }
  unassert(!"unexpected omni fd type");
}

static int OmniFdStatFill(struct OmniFdInfo *fdinfo, struct VfsDevice *device,
                          u64 ino, struct stat *st) {
  memset(st, 0, sizeof(*st));
  st->st_dev = device->dev;
  st->st_ino = ino;
  st->st_uid = getuid();
  st->st_gid = getgid();
  st->st_nlink = 1;
  st->st_blksize = 4096;
  st->st_mode = OmniFdMode(fdinfo->type);
  if (fdinfo->type == OMNI_FD_ROOT_DIR) {
    st->st_nlink = 2;
  }
  if (fdinfo->type == OMNI_FD_ROOT_LINK && fdinfo->link_target) {
    st->st_size = strlen(fdinfo->link_target);
  }
  return 0;
}

static int OmniFdParseName(const char *name, int *fd) {
  char *end;
  long value;

  if (!name || !*name) {
    return enoent();
  }
  errno = 0;
  value = strtol(name, &end, 10);
  if (errno || *end || value < 0 || value > INT_MAX) {
    return enoent();
  }
  *fd = (int)value;
  return 0;
}

static int OmniFdCreateInfo(struct VfsInfo *parent, const char *name,
                            enum OmniFdInfoType type, int guest_fd,
                            struct VfsInfo **output) {
  struct OmniFdInfo *fdinfo;

  *output = NULL;
  if (VfsCreateInfo(output) == -1) {
    return -1;
  }
  fdinfo = calloc(1, sizeof(*fdinfo));
  if (!fdinfo) {
    unassert(!VfsFreeInfo(*output));
    *output = NULL;
    return enomem();
  }
  fdinfo->type = type;
  fdinfo->guest_fd = guest_fd;
  fdinfo->link_target = parent && parent->data
                            ? ((struct OmniFdInfo *)parent->data)->link_target
                            : NULL;

  (*output)->data = fdinfo;
  (*output)->mode = OmniFdMode(type);
  (*output)->ino = type == OMNI_FD_ENTRY ? (u64)guest_fd + 2 : 1;
  (*output)->dev = 0;
  if (VfsAcquireDevice(parent->device, &(*output)->device) == -1) {
    unassert(!VfsFreeInfo(*output));
    *output = NULL;
    return -1;
  }
  if (VfsAcquireInfo(parent, &(*output)->parent) == -1) {
    unassert(!VfsFreeInfo(*output));
    *output = NULL;
    return -1;
  }
  (*output)->name = strdup(name);
  if (!(*output)->name) {
    unassert(!VfsFreeInfo(*output));
    *output = NULL;
    return enomem();
  }
  (*output)->namelen = strlen(name);
  return 0;
}

static int OmniFdEnsureOpendir(struct OmniFdInfo *fdinfo) {
  if (fdinfo->opendir) {
    return 0;
  }
  fdinfo->opendir = calloc(1, sizeof(*fdinfo->opendir));
  if (!fdinfo->opendir) {
    return enomem();
  }
  fdinfo->opendir->cursor_fd = -1;
  unassert(!pthread_mutex_init(&fdinfo->opendir->lock, NULL));
  return 0;
}

static int OmniFdInit(const char *source, u64 flags, const void *data,
                      struct VfsDevice **device, struct VfsMount **mount) {
  const struct OmniFdMountConfig *config = data;
  struct OmniFdInfo *rootinfo = NULL;

  (void)source;
  (void)flags;

  *device = NULL;
  *mount = NULL;

  if (VfsCreateDevice(device) == -1) {
    return -1;
  }
  (*device)->ops = &g_omni_fdfs.ops;

  *mount = calloc(1, sizeof(**mount));
  if (!*mount) {
    goto cleananddie;
  }
  if (VfsCreateInfo(&(*mount)->root) == -1) {
    goto cleananddie;
  }
  rootinfo = calloc(1, sizeof(*rootinfo));
  if (!rootinfo) {
    goto cleananddie;
  }
  if (!config) {
    config = &kOmniFdDirMount;
  }
  rootinfo->type = config->root_type;
  rootinfo->link_target = config->link_target;
  (*mount)->root->data = rootinfo;
  (*mount)->root->mode = OmniFdMode(rootinfo->type);
  (*mount)->root->ino = 1;
  if (VfsAcquireDevice(*device, &(*mount)->root->device) == -1) {
    goto cleananddie;
  }
  (*device)->root = (*mount)->root;
  return 0;

cleananddie:
  if (*mount) {
    if ((*mount)->root) {
      unassert(!VfsFreeInfo((*mount)->root));
    }
    free(*mount);
    *mount = NULL;
  }
  if (*device) {
    unassert(!VfsFreeDevice(*device));
    *device = NULL;
  } else {
    free(rootinfo);
  }
  return -1;
}

static int OmniFdFreeinfo(void *data) {
  struct OmniFdInfo *fdinfo = data;
  if (!fdinfo) {
    return 0;
  }
  if (fdinfo->opendir) {
    unassert(!pthread_mutex_destroy(&fdinfo->opendir->lock));
    free(fdinfo->opendir);
  }
  free(fdinfo);
  return 0;
}

static int OmniFdFreedevice(void *data) {
  (void)data;
  return 0;
}

static int OmniFdReadmountentry(struct VfsDevice *device, char **spec,
                                char **type, char **mntops) {
  (void)device;
  *spec = strdup("omni-fd");
  if (!*spec) {
    return enomem();
  }
  *type = strdup("omni-fd");
  if (!*type) {
    free(*spec);
    return enomem();
  }
  *mntops = NULL;
  return 0;
}

static int OmniFdFinddir(struct VfsInfo *parent, const char *name,
                         struct VfsInfo **output) {
  struct OmniFdInfo *parentinfo;
  struct VfsInfo *fdhandle;
  int guest_fd;

  if (!parent || !parent->data || !output) {
    return efault();
  }
  if (!strcmp(name, ".")) {
    return VfsAcquireInfo(parent, output);
  }
  if (!strcmp(name, "..")) {
    return VfsAcquireInfo(parent->parent ? parent->parent : parent, output);
  }
  parentinfo = parent->data;
  if (parentinfo->type != OMNI_FD_ROOT_DIR &&
      parentinfo->type != OMNI_FD_ROOT_LINK) {
    return enoent();
  }
  if (OmniFdParseName(name, &guest_fd) == -1) {
    return -1;
  }
  if (VfsGetFd(guest_fd, &fdhandle) == -1) {
    return -1;
  }
  unassert(!VfsFreeInfo(fdhandle));
  return OmniFdCreateInfo(parent, name, OMNI_FD_ENTRY, guest_fd, output);
}

static ssize_t OmniFdReadlink(struct VfsInfo *info, char **output) {
  struct OmniFdInfo *fdinfo;

  if (!info || !info->data || !output) {
    return efault();
  }
  fdinfo = info->data;
  if (fdinfo->type != OMNI_FD_ROOT_LINK || !fdinfo->link_target) {
    return einval();
  }
  *output = strdup(fdinfo->link_target);
  if (!*output) {
    return enomem();
  }
  return strlen(*output);
}

static int OmniFdOpenRoot(struct VfsInfo *info, struct VfsInfo **output) {
  enum OmniFdInfoType type = OMNI_FD_ROOT_DIR;

  if (((struct OmniFdInfo *)info->data)->type == OMNI_FD_ROOT_DIR) {
    type = OMNI_FD_ROOT_DIR;
  }
  if (OmniFdCreateInfo(info->parent, info->name ? info->name : ".", type, -1,
                       output) == -1) {
    return -1;
  }
  if (OmniFdEnsureOpendir((*output)->data) == -1) {
    unassert(!VfsFreeInfo(*output));
    *output = NULL;
    return -1;
  }
  return 0;
}

static int OmniFdOpen(struct VfsInfo *parent, const char *name, int flags,
                      int mode, struct VfsInfo **output) {
  struct VfsInfo *info = NULL;
  struct OmniFdInfo *fdinfo;
  struct VfsInfo *guestinfo = NULL;
  int rc = -1;

  (void)mode;

  if (OmniFdFinddir(parent, name, &info) == -1) {
    return -1;
  }
  fdinfo = info->data;
  if (fdinfo->type == OMNI_FD_ROOT_DIR || fdinfo->type == OMNI_FD_ROOT_LINK) {
    rc = OmniFdOpenRoot(info, output);
  } else {
    if (flags & O_DIRECTORY) {
      enotdir();
      goto done;
    }
    if (VfsGetFd(fdinfo->guest_fd, &guestinfo) == -1) {
      goto done;
    }
    if (!guestinfo->device->ops->Dup) {
      eperm();
      goto done;
    }
    rc = guestinfo->device->ops->Dup(guestinfo, output);
  }

done:
  unassert(!VfsFreeInfo(guestinfo));
  unassert(!VfsFreeInfo(info));
  return rc;
}

static int OmniFdAccess(struct VfsInfo *parent, const char *name, mode_t mode,
                        int flags) {
  struct VfsInfo *info = NULL;
  struct OmniFdInfo *fdinfo;
  int rc = 0;
  mode_t perms;

  (void)flags;
  if (OmniFdFinddir(parent, name, &info) == -1) {
    return -1;
  }
  fdinfo = info->data;
  perms = fdinfo->type == OMNI_FD_ROOT_LINK ? 0777 :
          fdinfo->type == OMNI_FD_ROOT_DIR  ? 0555 :
                                              0666;
  if (mode != F_OK) {
    if ((mode & R_OK) && !(perms & 0444)) {
      rc = eacces();
    } else if ((mode & W_OK) && !(perms & 0222)) {
      rc = eacces();
    } else if ((mode & X_OK) && !(perms & 0111)) {
      rc = eacces();
    }
  }
  unassert(!VfsFreeInfo(info));
  return rc;
}

static int OmniFdStat(struct VfsInfo *parent, const char *name, struct stat *st,
                      int flags) {
  struct VfsInfo *info = NULL;
  struct OmniFdInfo *fdinfo;
  int rc;

  (void)flags;
  if (OmniFdFinddir(parent, name, &info) == -1) {
    return -1;
  }
  fdinfo = info->data;
  rc = OmniFdStatFill(fdinfo, parent->device, info->ino, st);
  unassert(!VfsFreeInfo(info));
  return rc;
}

static int OmniFdFstat(struct VfsInfo *info, struct stat *st) {
  if (!info || !info->data) {
    return efault();
  }
  return OmniFdStatFill(info->data, info->device, info->ino, st);
}

static int OmniFdClose(struct VfsInfo *info) {
  struct OmniFdInfo *fdinfo;

  if (!info || !info->data) {
    return 0;
  }
  fdinfo = info->data;
  if (fdinfo->opendir) {
    unassert(!pthread_mutex_destroy(&fdinfo->opendir->lock));
    free(fdinfo->opendir);
    fdinfo->opendir = NULL;
  }
  return 0;
}

static int OmniFdDup(struct VfsInfo *info, struct VfsInfo **output) {
  struct OmniFdInfo *fdinfo;

  if (!info || !info->data) {
    return efault();
  }
  fdinfo = info->data;
  if (fdinfo->type != OMNI_FD_ROOT_DIR && fdinfo->type != OMNI_FD_ROOT_LINK) {
    return eperm();
  }
  if (OmniFdCreateInfo(info->parent, info->name ? info->name : ".",
                       fdinfo->type, -1, output) == -1) {
    return -1;
  }
  if (OmniFdEnsureOpendir((*output)->data) == -1) {
    unassert(!VfsFreeInfo(*output));
    *output = NULL;
    return -1;
  }
  ((struct OmniFdInfo *)(*output)->data)->opendir->index = fdinfo->opendir
                                                               ? fdinfo->opendir->index
                                                               : 0;
  ((struct OmniFdInfo *)(*output)->data)->opendir->cursor_fd = fdinfo->opendir
                                                                   ? fdinfo->opendir->cursor_fd
                                                                   : -1;
  return 0;
}

static int OmniFdOpendir(struct VfsInfo *info, struct VfsInfo **output) {
  struct OmniFdInfo *fdinfo;

  if (!info || !info->data) {
    return efault();
  }
  fdinfo = info->data;
  if (fdinfo->type != OMNI_FD_ROOT_DIR || !fdinfo->opendir) {
    return einval();
  }
  return VfsAcquireInfo(info, output);
}

static void OmniFdSeekdir(struct VfsInfo *info, long loc) {
  struct OmniFdInfo *fdinfo;
  int nextfd = -1;

  if (!info || !info->data) {
    return;
  }
  fdinfo = info->data;
  if (fdinfo->type != OMNI_FD_ROOT_DIR || !fdinfo->opendir) {
    return;
  }
  if (loc < 0) {
    loc = 0;
  }
  LOCK(&fdinfo->opendir->lock);
  fdinfo->opendir->index = loc;
  fdinfo->opendir->cursor_fd = -1;
  for (long i = 2; i < loc; ++i) {
    nextfd = VfsNextFd(fdinfo->opendir->cursor_fd);
    if (nextfd == -1) {
      break;
    }
    fdinfo->opendir->cursor_fd = nextfd;
  }
  UNLOCK(&fdinfo->opendir->lock);
}

static long OmniFdTelldir(struct VfsInfo *info) {
  struct OmniFdInfo *fdinfo;

  if (!info || !info->data) {
    return 0;
  }
  fdinfo = info->data;
  if (fdinfo->type != OMNI_FD_ROOT_DIR || !fdinfo->opendir) {
    return 0;
  }
  return fdinfo->opendir->index;
}

static struct dirent *OmniFdReaddir(struct VfsInfo *info) {
  static _Thread_local char buf[sizeof(struct dirent) + VFS_NAME_MAX];
  struct dirent *de = (struct dirent *)buf;
  struct OmniFdInfo *fdinfo;
  int nextfd;

  if (!info || !info->data) {
    errno = EINVAL;
    return NULL;
  }
  fdinfo = info->data;
  if (fdinfo->type != OMNI_FD_ROOT_DIR || !fdinfo->opendir) {
    errno = EINVAL;
    return NULL;
  }

  LOCK(&fdinfo->opendir->lock);
  if (fdinfo->opendir->index == 0) {
    de->d_ino = info->parent ? info->parent->ino : info->ino;
#ifdef DT_DIR
    de->d_type = DT_DIR;
#endif
    strcpy(de->d_name, "..");
  } else if (fdinfo->opendir->index == 1) {
    de->d_ino = info->ino;
#ifdef DT_DIR
    de->d_type = DT_DIR;
#endif
    strcpy(de->d_name, ".");
  } else {
    nextfd = VfsNextFd(fdinfo->opendir->cursor_fd);
    if (nextfd == -1) {
      UNLOCK(&fdinfo->opendir->lock);
      errno = 0;
      return NULL;
    }
    fdinfo->opendir->cursor_fd = nextfd;
    de->d_ino = (ino_t)nextfd + 2;
#ifdef DT_CHR
    de->d_type = DT_CHR;
#endif
    snprintf(de->d_name, VFS_NAME_MAX, "%d", nextfd);
  }
  ++fdinfo->opendir->index;
  UNLOCK(&fdinfo->opendir->lock);
  return de;
}

static void OmniFdRewinddir(struct VfsInfo *info) {
  OmniFdSeekdir(info, 0);
}

static int OmniFdClosedir(struct VfsInfo *info) {
  unassert(!VfsFreeInfo(info));
  return OmniFdClose(info);
}

int OmniInstallGuestFdMounts(void) {
  struct stat st;

  if (VfsRegister(&g_omni_fdfs) == -1) {
    return -1;
  }
  if (VfsMount("", "/proc/self/fd", "omni-fd", 0, &kOmniFdDirMount) == -1) {
    return -1;
  }
  if (stat("/dev/fd", &st) == 0 && S_ISDIR(st.st_mode)) {
    if (VfsMount("", "/dev/fd", "omni-fd", 0, &kOmniFdDevLinkMount) == -1) {
      return -1;
    }
  }
  return 0;
}
