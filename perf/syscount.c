// Syscall counter for the perf harness.
//
// macOS `dtruss` needs root (and `sudo -n` is not available on this machine),
// so the harness counts the syscalls that matter for the TUI write path by
// interposing them with DYLD_INSERT_LIBRARIES instead. Counting happens in the
// process under test; the totals are appended to $SYSCOUNT_OUT at exit as one
// `key=value` line.
//
// Build: clang -dynamiclib -O2 -o syscount.dylib syscount.c
// Use:   DYLD_INSERT_LIBRARIES=.../syscount.dylib SYSCOUNT_OUT=... nvim ...

#include <fcntl.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

struct kevent;
struct timespec;
struct pollfd;

#define DYLD_INTERPOSE(_replacement, _replacee)                                                    \
  __attribute__((used)) static struct {                                                            \
    const void *replacement;                                                                       \
    const void *replacee;                                                                          \
  } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {                      \
    (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee            \
  };

// ioctl() is variadic: interposing it with a fixed-arity function breaks the
// arm64 varargs ABI (crash), so it is deliberately not counted.
static long n_write, n_writev, n_read, n_readv, n_kevent, n_poll, n_select, n_sendto;
static long bytes_written;
static int reporting;

#define BUMP(c) __atomic_fetch_add(&(c), 1, __ATOMIC_RELAXED)
#define BUMPN(c, n) __atomic_fetch_add(&(c), (long)(n), __ATOMIC_RELAXED)

static ssize_t sc_write(int fd, const void *buf, size_t n)
{
  if (!reporting) {
    BUMP(n_write);
  }
  ssize_t r = write(fd, buf, n);
  if (!reporting && r > 0) {
    BUMPN(bytes_written, r);
  }
  return r;
}

static ssize_t sc_writev(int fd, const struct iovec *iov, int cnt)
{
  if (!reporting) {
    BUMP(n_writev);
  }
  ssize_t r = writev(fd, iov, cnt);
  if (!reporting && r > 0) {
    BUMPN(bytes_written, r);
  }
  return r;
}

static ssize_t sc_read(int fd, void *buf, size_t n)
{
  BUMP(n_read);
  return read(fd, buf, n);
}

static ssize_t sc_readv(int fd, const struct iovec *iov, int cnt)
{
  BUMP(n_readv);
  return readv(fd, iov, cnt);
}

extern int kevent(int, const struct kevent *, int, struct kevent *, int, const struct timespec *);
static int sc_kevent(int kq, const struct kevent *cl, int nc, struct kevent *el, int ne,
                     const struct timespec *ts)
{
  BUMP(n_kevent);
  return kevent(kq, cl, nc, el, ne, ts);
}

extern int poll(struct pollfd *, unsigned int, int);
static int sc_poll(struct pollfd *fds, unsigned int n, int timeout)
{
  BUMP(n_poll);
  return poll(fds, n, timeout);
}

static int sc_select(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *t)
{
  BUMP(n_select);
  return select(n, r, w, e, t);
}

static ssize_t sc_sendto(int fd, const void *buf, size_t n, int flags, const struct sockaddr *to,
                         socklen_t tolen)
{
  BUMP(n_sendto);
  ssize_t r = sendto(fd, buf, n, flags, to, tolen);
  if (r > 0) {
    BUMPN(bytes_written, r);
  }
  return r;
}

DYLD_INTERPOSE(sc_write, write)
DYLD_INTERPOSE(sc_writev, writev)
DYLD_INTERPOSE(sc_read, read)
DYLD_INTERPOSE(sc_readv, readv)
DYLD_INTERPOSE(sc_kevent, kevent)
DYLD_INTERPOSE(sc_poll, poll)
DYLD_INTERPOSE(sc_select, select)
DYLD_INTERPOSE(sc_sendto, sendto)

static void sc_report(void)
{
  const char *out = getenv("SYSCOUNT_OUT");
  if (out == NULL || reporting) {
    return;
  }
  reporting = 1;  // Stop counting our own report.
  char buf[2048];
  // pid/ppid so a report from a forked helper is never mistaken for the
  // process under test.
  char exe[1024] = "?";
  proc_pidpath(getpid(), exe, sizeof(exe));
  int len = snprintf(buf, sizeof(buf),
                     "exe=%s pid=%d ppid=%d write=%ld writev=%ld read=%ld readv=%ld kevent=%ld poll=%ld "
                     "select=%ld sendto=%ld bytes_written=%ld\n",
                     exe, (int)getpid(), (int)getppid(), n_write, n_writev, n_read, n_readv, n_kevent,
                     n_poll, n_select, n_sendto, bytes_written);
  int fd = open(out, O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd >= 0) {
    ssize_t rv = write(fd, buf, (size_t)len);
    (void)rv;
    close(fd);
  }
}

__attribute__((destructor)) static void sc_fini(void)
{
  sc_report();
}

__attribute__((constructor)) static void sc_init(void)
{
  atexit(sc_report);
}
