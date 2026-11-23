// Linux resource accounting and cleanup for one local command.
#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static long long monotonic_us() {
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * 1000000LL + now.tv_nsec / 1000;
}

static long long micros(timeval time) {
    return time.tv_sec * 1000000LL + time.tv_usec;
}

static bool set_limit(int resource, rlim_t soft, rlim_t hard) {
    const rlimit limit{soft, hard};
    return setrlimit(resource, &limit) == 0;
}

static void child_error(int fd) {
    const int saved_errno = errno;
    ssize_t written;
    do {
        written = write(fd, &saved_errno, sizeof saved_errno);
    } while (written < 0 && errno == EINTR);
    _exit(127);
}

static void run_child(char** command, int error_fd, pid_t parent, const sigset_t& original_mask,
                      rlim_t cpu, rlim_t address_space, rlim_t file_size) {
    if (setpgid(0, 0) != 0 || prctl(PR_SET_PDEATHSIG, SIGKILL) != 0) {
        child_error(error_fd);
    }
    if (getppid() != parent) {
        _exit(127);
    }
    signal(SIGPIPE, SIG_DFL);
    sigprocmask(SIG_SETMASK, &original_mask, nullptr);
    if (!set_limit(RLIMIT_CORE, 0, 0)
        || !set_limit(RLIMIT_FSIZE, file_size, file_size)
        || (cpu && !set_limit(RLIMIT_CPU, cpu, cpu + 1))
        || (address_space && !set_limit(RLIMIT_AS, address_space, address_space))) {
        child_error(error_fd);
    }
    execvp(command[0], command);
    child_error(error_fd);
}

static void reap_adopted_children() {
    // A child that detached from the original group can be adopted as its
    // parent exits. Only signal our own children, which cannot reuse their PIDs
    // before we wait for them.
    char path[96];
    const int self = getpid();
    snprintf(path, sizeof path, "/proc/self/task/%d/children", self);
    const long long deadline = monotonic_us() + 1000000;
    while (monotonic_us() < deadline) {
        const pid_t child = waitpid(-1, nullptr, WNOHANG);
        if (child > 0 || (child == -1 && errno == EINTR)) {
            continue;
        }
        if (child < 0) {
            return;
        }
        FILE* list = fopen(path, "r");
        if (list) {
            int pid;
            while (fscanf(list, "%d", &pid) == 1) {
                if (pid > 0) {
                    kill(pid, SIGKILL);
                }
            }
            fclose(list);
        }
        const timespec pause{0, 1000000};
        nanosleep(&pause, nullptr);
    }
}

int main(int argc, char** argv) {
    // metrics-file wall-ms cpu-seconds address-space-bytes file-size-bytes parent-pid command...
    if (argc < 8) {
        return 125;
    }
    const long long timeout_us = strtoll(argv[2], nullptr, 10) * 1000;
    const rlim_t cpu = strtoull(argv[3], nullptr, 10);
    const rlim_t address_space = strtoull(argv[4], nullptr, 10);
    const rlim_t file_size = strtoull(argv[5], nullptr, 10);
    const long expected_parent = strtol(argv[6], nullptr, 10);
    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGTERM);
    sigaddset(&blocked, SIGCHLD);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) < 0
        || prctl(PR_SET_PDEATHSIG, SIGTERM) != 0
        || prctl(PR_SET_CHILD_SUBREAPER, 1) != 0) {
        perror("runner setup");
        return 125;
    }
    if (getppid() != expected_parent) {
        return 125;
    }

    int child_errors[2];
    if (pipe2(child_errors, O_CLOEXEC | O_NONBLOCK) != 0) {
        perror("pipe2");
        return 125;
    }
    const pid_t self = getpid();
    const long long started = monotonic_us();
    const pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return 125;
    }
    if (child == 0) {
        close(child_errors[0]);
        run_child(argv + 7, child_errors[1], self, previous, cpu, address_space, file_size);
    }
    close(child_errors[1]);
    close(STDIN_FILENO);
    // Both parent and child set the group so early cancellation can always
    // find it. The child's call covers the race where it has already exec'd.
    setpgid(child, child);
    const char* reason = "exit";
    for (;;) {
        siginfo_t info{};
        if (waitid(P_PID, child, &info, WEXITED | WNOHANG | WNOWAIT) == 0 && info.si_pid == child) {
            break;
        }
        const long long remaining = timeout_us - (monotonic_us() - started);
        if (remaining <= 0) {
            reason = "wall";
            break;
        }
        const timespec timeout{static_cast<time_t>(remaining / 1000000),
                               static_cast<long>((remaining % 1000000) * 1000)};
        if (sigtimedwait(&blocked, nullptr, &timeout) == SIGTERM) {
            reason = "stop";
            break;
        }
    }
    const long long elapsed = monotonic_us() - started;
    kill(-child, SIGKILL);
    int status = 0;
    rusage usage{};
    pid_t waited;
    do {
        waited = wait4(child, &status, 0, &usage);
    } while (waited < 0 && errno == EINTR);
    int setup_errno = 0;
    if (read(child_errors[0], &setup_errno, sizeof setup_errno) != sizeof setup_errno) {
        setup_errno = 0;
    }
    close(child_errors[0]);
    reap_adopted_children();

    if (waited < 0) {
        perror("wait4");
        return 125;
    }
    if (setup_errno) {
        errno = setup_errno;
        perror("runner child setup / exec");
    }
    if (std::strcmp(reason, "exit") == 0 && WIFSIGNALED(status)) {
        if (WTERMSIG(status) == SIGXCPU) {
            reason = "cpu";
        } else if (WTERMSIG(status) == SIGXFSZ) {
            reason = "file";
        }
    }
    const int fd = open(argv[1], O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
    if (fd < 0) {
        perror("create metrics");
        return 125;
    }
    const int written = dprintf(fd, "%s %lld %lld %lld %ld %d %d %d\n", reason, elapsed,
                                micros(usage.ru_utime), micros(usage.ru_stime), usage.ru_maxrss,
                                WIFEXITED(status) ? WEXITSTATUS(status) : -1,
                                WIFSIGNALED(status) ? WTERMSIG(status) : 0, setup_errno);
    const int closed = close(fd);
    return written < 0 || closed < 0 ? 125 : 0;
}
