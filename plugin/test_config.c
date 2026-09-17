#include "svport.c"
#include <sys/stat.h>

static int failures;

static void write_cfg(const char *dir, const char *content, size_t length)
{
    char path[256];
    FILE *file;
    mkdir(dir, 0755);
    snprintf(path, sizeof(path), "%s/server.cfg", dir);
    file = fopen(path, "wb");
    fwrite(content, 1, length, file);
    fclose(file);
}

static void check(const char *name, const char *content, size_t length, const char *env, unsigned int want_port, const char *want_ip)
{
    char dir[128];
    char ip[INET_ADDRSTRLEN];
    char cwd[512];
    snprintf(dir, sizeof(dir), "/tmp/svport-test-%s", name);
    write_cfg(dir, content, length);
    if (env)
        setenv("SV_PORT", env, 1);
    else
        unsetenv("SV_PORT");
    getcwd(cwd, sizeof(cwd));
    chdir(dir);
    read_config();
    chdir(cwd);
    inet_ntop(AF_INET, &voice_ip, ip, sizeof(ip));
    if (voice_port != want_port || strcmp(ip, want_ip) != 0) {
        printf("FAIL %s: port=%u ip=%s (want %u %s)\n", name, voice_port, ip, want_port, want_ip);
        ++failures;
    } else {
        printf("ok   %s: port=%u ip=%s\n", name, voice_port, ip);
    }
}

int main(void)
{
    char longline[1400];
    char buffer[1600];
    int length;
    memset(longline, 'x', sizeof(longline));
    memcpy(longline, "plugins ", 8);
    memcpy(longline + 600, " sv_port 9999 ", 14);
    longline[sizeof(longline) - 1] = '\0';
    check("plain", "port 7777\nsv_port 3000\n", 23, NULL, 3000, "0.0.0.0");
    check("crlf", "port 7777\r\nsv_port 3000\r\n", 25, NULL, 3000, "0.0.0.0");
    check("bom", "\xEF\xBB\xBFsv_port 3001\nport 7777\n", 30, NULL, 3001, "0.0.0.0");
    length = snprintf(buffer, sizeof(buffer), "port 7777\n%s\nsv_port 3002\n", longline);
    check("longline", buffer, (size_t)length, NULL, 3002, "0.0.0.0");
    length = snprintf(buffer, sizeof(buffer), "port 7777\n%s\n", longline);
    check("longline-only", buffer, (size_t)length, NULL, 0, "0.0.0.0");
    check("same-as-game", "port 7777\nsv_port 7777\n", 23, NULL, 0, "0.0.0.0");
    check("invalid", "port 7777\nsv_port abc\n", 22, NULL, 0, "0.0.0.0");
    check("env", "port 7777\n", 10, "3003", 3003, "0.0.0.0");
    check("cfg-over-env", "port 7777\nsv_port 3000\n", 23, "3003", 3000, "0.0.0.0");
    check("bind", "port 7777\nbind 10.1.2.3\nsv_port 3004\n", 37, NULL, 3004, "10.1.2.3");
    check("tabs-case", "port 7777\n\tSV_PORT\t3005\t\n", 26, NULL, 3005, "0.0.0.0");
    check("range", "port 7777\nsv_port 70000\n", 24, NULL, 0, "0.0.0.0");
    printf("%s\n", failures ? "TESTS FAILED" : "ALL TESTS PASSED");
    return failures != 0;
}
