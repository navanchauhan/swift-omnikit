(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "hello\n")
  (func (export "_start")
    ;; iov_base = 0, iov_len = 6
    (i32.store (i32.const 100) (i32.const 0))
    (i32.store (i32.const 104) (i32.const 6))
    ;; fd_write(fd=1, iovs=100, iovs_len=1, nwritten=200)
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 200)))
  )
)
