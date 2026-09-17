#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <link.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

#define SVPORT_VERSION "0.1.1"
#define SVPORT_EXPORT __attribute__((visibility("default")))
#define SUPPORTS_VERSION 0x0200
#define PLUGIN_DATA_LOGPRINTF 0x00

__asm__(
    ".section .rodata\n"
    ".balign 16\n"
    ".hidden svport_core_begin\n"
    ".globl svport_core_begin\n"
    "svport_core_begin:\n"
    ".incbin \"" SVPORT_CORE_PATH "\"\n"
    ".hidden svport_core_end\n"
    ".globl svport_core_end\n"
    "svport_core_end:\n"
    ".previous\n"
);

extern const unsigned char svport_core_begin[];
extern const unsigned char svport_core_end[];

typedef void (*logprintf_t)(const char *format, ...);
typedef unsigned int (*supports_t)(void);
typedef int (*load_t)(void **data);
typedef void (*unload_t)(void);
typedef int (*amx_t)(void *amx);
typedef void (*tick_t)(void);

static logprintf_t logprintf_fn;
static void *core_handle;
static int core_state;
static char core_error[256];
static supports_t core_supports;
static load_t core_load;
static unload_t core_unload;
static amx_t core_amx_load;
static amx_t core_amx_unload;
static tick_t core_process_tick;

static unsigned int voice_port;
static unsigned int game_port;
static struct in_addr voice_ip;

static void say(const char *format, ...)
{
    char line[512];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    if (logprintf_fn != NULL)
        logprintf_fn("[svport] %s", line);
    else
        fprintf(stderr, "[svport] %s\n", line);
}

static int parse_port(const char *text, unsigned int *out)
{
    unsigned long value = 0;
    int digits = 0;
    while (*text == ' ' || *text == '\t')
        ++text;
    while (*text >= '0' && *text <= '9') {
        value = value * 10 + (unsigned long)(*text - '0');
        if (value > 65535)
            return 0;
        ++text;
        ++digits;
    }
    while (*text == ' ' || *text == '\t' || *text == '\r' || *text == '\n')
        ++text;
    if (digits == 0 || *text != '\0' || value == 0)
        return 0;
    *out = (unsigned int)value;
    return 1;
}

static void trim(char *text)
{
    size_t length = strlen(text);
    while (length > 0 && (text[length - 1] == '\r' || text[length - 1] == '\n' || text[length - 1] == ' ' || text[length - 1] == '\t'))
        text[--length] = '\0';
}

static void read_config(void)
{
    char line[512];
    char bind_value[64] = "";
    char port_value[64] = "";
    char game_value[64] = "";
    FILE *file = fopen("server.cfg", "r");
    if (file != NULL) {
        int continuation = 0;
        int first = 1;
        while (fgets(line, sizeof(line), file) != NULL) {
            char *key = line;
            char *value;
            int skip = continuation;
            continuation = strchr(line, '\n') == NULL && !feof(file);
            if (skip)
                continue;
            if (first) {
                first = 0;
                if ((unsigned char)key[0] == 0xEF && (unsigned char)key[1] == 0xBB && (unsigned char)key[2] == 0xBF)
                    key += 3;
            }
            while (*key == ' ' || *key == '\t')
                ++key;
            value = key;
            while (*value != '\0' && *value != ' ' && *value != '\t' && *value != '\r' && *value != '\n')
                ++value;
            if (*value != '\0') {
                *value++ = '\0';
                while (*value == ' ' || *value == '\t')
                    ++value;
            }
            trim(value);
            if (strcasecmp(key, "sv_port") == 0)
                snprintf(port_value, sizeof(port_value), "%s", value);
            else if (strcasecmp(key, "bind") == 0)
                snprintf(bind_value, sizeof(bind_value), "%s", value);
            else if (strcasecmp(key, "port") == 0)
                snprintf(game_value, sizeof(game_value), "%s", value);
        }
        fclose(file);
    } else {
        say("server.cfg not found in %s (%s)", getcwd(line, sizeof(line)) ? line : "?", strerror(errno));
    }

    if (port_value[0] == '\0') {
        const char *env = getenv("SV_PORT");
        if (env != NULL && env[0] != '\0') {
            snprintf(port_value, sizeof(port_value), "%s", env);
            say("sv_port taken from the SV_PORT environment variable");
        }
    }

    game_port = 0;
    if (game_value[0] != '\0' && !parse_port(game_value, &game_port))
        game_port = 0;

    voice_port = 0;
    if (port_value[0] == '\0') {
        say("sv_port is not set: add 'sv_port <port>' to server.cfg (the voice port will be random)");
    } else if (!parse_port(port_value, &voice_port)) {
        voice_port = 0;
        say("sv_port '%s' is not a valid port (1-65535): the voice port will be random", port_value);
    } else if (game_port != 0 && voice_port == game_port) {
        say("sv_port %u is the game port: use a different allocation (the voice port will be random)", voice_port);
        voice_port = 0;
    }

    voice_ip.s_addr = htonl(INADDR_ANY);
    if (bind_value[0] != '\0') {
        struct in_addr parsed;
        if (inet_pton(AF_INET, bind_value, &parsed) == 1)
            voice_ip = parsed;
        else
            say("bind '%s' is not an IPv4 address: voice listens on 0.0.0.0", bind_value);
    }
}

static int svport_bind(int fd, const struct sockaddr *addr, socklen_t length)
{
    if (voice_port != 0 && addr != NULL && length >= (socklen_t)sizeof(struct sockaddr_in) && addr->sa_family == AF_INET) {
        const struct sockaddr_in *requested = (const struct sockaddr_in *)addr;
        int type = 0;
        socklen_t type_length = sizeof(type);
        if (requested->sin_port == 0 && getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &type_length) == 0 && type == SOCK_DGRAM) {
            struct sockaddr_in forced = *requested;
            char address[INET_ADDRSTRLEN];
            int error;
            forced.sin_port = htons((unsigned short)voice_port);
            if (voice_ip.s_addr != htonl(INADDR_ANY))
                forced.sin_addr = voice_ip;
            inet_ntop(AF_INET, &forced.sin_addr, address, sizeof(address));
            if (bind(fd, (const struct sockaddr *)&forced, sizeof(forced)) == 0) {
                say("voice socket bound to %s:%u/udp", address, voice_port);
                return 0;
            }
            error = errno;
            say("could not bind voice to %s:%u/udp (%s): falling back to a random port, voice will not work behind a firewall", address, voice_port, strerror(error));
        }
    }
    return bind(fd, addr, length);
}

static int svport_mprotect(void *address, size_t length, int protection)
{
    if (protection == (PROT_READ | PROT_EXEC))
        protection |= PROT_WRITE;
    return mprotect(address, length, protection);
}

static ElfW(Addr) absolute(ElfW(Addr) base, ElfW(Addr) pointer)
{
    return pointer < base ? base + pointer : pointer;
}

struct relro_search {
    ElfW(Addr) base;
    ElfW(Addr) start;
    ElfW(Addr) end;
    int found;
};

static int find_relro(struct dl_phdr_info *info, size_t size, void *data)
{
    struct relro_search *search = data;
    ElfW(Half) index;
    (void)size;
    if (info->dlpi_addr != search->base)
        return 0;
    for (index = 0; index < info->dlpi_phnum; ++index) {
        if (info->dlpi_phdr[index].p_type == PT_GNU_RELRO) {
            search->start = info->dlpi_addr + info->dlpi_phdr[index].p_vaddr;
            search->end = search->start + info->dlpi_phdr[index].p_memsz;
            search->found = 1;
        }
    }
    return 1;
}

static int write_slot(void **slot, void *value, const struct relro_search *relro)
{
    long page = sysconf(_SC_PAGESIZE);
    ElfW(Addr) address = (ElfW(Addr))slot;
    ElfW(Addr) page_start = address & ~((ElfW(Addr))page - 1);
    int protected_slot = relro->found && address >= relro->start && address < relro->end;
    if (protected_slot && mprotect((void *)page_start, (size_t)page, PROT_READ | PROT_WRITE) != 0)
        return 0;
    *slot = value;
    if (protected_slot)
        mprotect((void *)page_start, (size_t)page, PROT_READ);
    return 1;
}

static int patch_symbol(void *handle, const char *symbol, void *replacement)
{
    struct link_map *map = NULL;
    struct relro_search relro;
    ElfW(Dyn) *entry;
    ElfW(Sym) *symbols = NULL;
    const char *strings = NULL;
    ElfW(Rel) *tables[2] = { NULL, NULL };
    size_t sizes[2] = { 0, 0 };
    int patched = 0;
    int table;

    if (dlinfo(handle, RTLD_DI_LINKMAP, &map) != 0 || map == NULL || map->l_ld == NULL)
        return -1;

    for (entry = map->l_ld; entry->d_tag != DT_NULL; ++entry) {
        switch (entry->d_tag) {
        case DT_SYMTAB:
            symbols = (ElfW(Sym) *)absolute(map->l_addr, entry->d_un.d_ptr);
            break;
        case DT_STRTAB:
            strings = (const char *)absolute(map->l_addr, entry->d_un.d_ptr);
            break;
        case DT_JMPREL:
            tables[0] = (ElfW(Rel) *)absolute(map->l_addr, entry->d_un.d_ptr);
            break;
        case DT_PLTRELSZ:
            sizes[0] = entry->d_un.d_val;
            break;
        case DT_REL:
            tables[1] = (ElfW(Rel) *)absolute(map->l_addr, entry->d_un.d_ptr);
            break;
        case DT_RELSZ:
            sizes[1] = entry->d_un.d_val;
            break;
        default:
            break;
        }
    }

    if (symbols == NULL || strings == NULL)
        return -1;

    memset(&relro, 0, sizeof(relro));
    relro.base = map->l_addr;
    dl_iterate_phdr(find_relro, &relro);

    for (table = 0; table < 2; ++table) {
        size_t index;
        if (tables[table] == NULL)
            continue;
        for (index = 0; index < sizes[table] / sizeof(ElfW(Rel)); ++index) {
            const ElfW(Rel) *relocation = &tables[table][index];
            unsigned type = ELF32_R_TYPE(relocation->r_info);
            unsigned symbol_index = ELF32_R_SYM(relocation->r_info);
            if ((type != R_386_JMP_SLOT && type != R_386_GLOB_DAT) || symbol_index == 0)
                continue;
            if (strcmp(strings + symbols[symbol_index].st_name, symbol) != 0)
                continue;
            if (!write_slot((void **)(map->l_addr + relocation->r_offset), replacement, &relro))
                return -1;
            ++patched;
        }
    }
    return patched;
}

static void *open_core(void)
{
    size_t size = (size_t)(svport_core_end - svport_core_begin);
    char path[64];
    void *handle;
    int fd = (int)syscall(SYS_memfd_create, "sampvoice-core", 1U);
    if (fd >= 0) {
        size_t written = 0;
        while (written < size) {
            ssize_t chunk = write(fd, svport_core_begin + written, size - written);
            if (chunk <= 0)
                break;
            written += (size_t)chunk;
        }
        if (written == size) {
            snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
            handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
            close(fd);
            if (handle != NULL)
                return handle;
            snprintf(core_error, sizeof(core_error), "dlopen(memfd) failed: %s", dlerror());
        } else {
            close(fd);
        }
    }

    snprintf(path, sizeof(path), "/tmp/sampvoice-core-XXXXXX");
    fd = mkstemp(path);
    if (fd < 0) {
        snprintf(core_error, sizeof(core_error), "cannot create a temporary core file: %s", strerror(errno));
        return NULL;
    }
    {
        size_t written = 0;
        while (written < size) {
            ssize_t chunk = write(fd, svport_core_begin + written, size - written);
            if (chunk <= 0)
                break;
            written += (size_t)chunk;
        }
        close(fd);
        if (written != size) {
            unlink(path);
            snprintf(core_error, sizeof(core_error), "cannot write the temporary core file");
            return NULL;
        }
    }
    handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    unlink(path);
    if (handle == NULL)
        snprintf(core_error, sizeof(core_error), "dlopen(%s) failed: %s", path, dlerror());
    return handle;
}

static int ensure_core(void)
{
    if (core_state != 0)
        return core_state > 0;
    core_state = -1;
    core_handle = open_core();
    if (core_handle == NULL)
        return 0;
    core_supports = (supports_t)dlsym(core_handle, "Supports");
    core_load = (load_t)dlsym(core_handle, "Load");
    core_unload = (unload_t)dlsym(core_handle, "Unload");
    core_amx_load = (amx_t)dlsym(core_handle, "AmxLoad");
    core_amx_unload = (amx_t)dlsym(core_handle, "AmxUnload");
    core_process_tick = (tick_t)dlsym(core_handle, "ProcessTick");
    if (core_supports == NULL || core_load == NULL || core_unload == NULL || core_amx_load == NULL || core_amx_unload == NULL) {
        snprintf(core_error, sizeof(core_error), "the embedded core does not export the SA-MP plugin interface");
        return 0;
    }
    core_state = 1;
    return 1;
}

SVPORT_EXPORT unsigned int Supports(void)
{
    if (!ensure_core()) {
        say("cannot load the embedded SampVoice core: %s", core_error);
        return SUPPORTS_VERSION;
    }
    return core_supports();
}

SVPORT_EXPORT int Load(void **data)
{
    int patched;
    logprintf_fn = (logprintf_t)data[PLUGIN_DATA_LOGPRINTF];
    say("SampVoice fixed-port loader %s (embedded core: SampVoice 3.1)", SVPORT_VERSION);
    if (!ensure_core()) {
        say("cannot load the embedded SampVoice core: %s", core_error);
        return 0;
    }
    read_config();
    patched = patch_symbol(core_handle, "mprotect", (void *)svport_mprotect);
    if (patched <= 0)
        say("could not hook the core's mprotect() (%d): Pawn.RakNet may crash when loaded together", patched);
    if (voice_port != 0) {
        patched = patch_symbol(core_handle, "bind", (void *)svport_bind);
        if (patched > 0) {
            say("voice port set to %u/udp from server.cfg", voice_port);
        } else {
            say("could not hook the core's bind() (%d): the voice port will be random", patched);
        }
    }
    return core_load(data);
}

SVPORT_EXPORT void Unload(void)
{
    if (core_state > 0)
        core_unload();
}

SVPORT_EXPORT int AmxLoad(void *amx)
{
    return core_state > 0 ? core_amx_load(amx) : 0;
}

SVPORT_EXPORT int AmxUnload(void *amx)
{
    return core_state > 0 ? core_amx_unload(amx) : 0;
}

SVPORT_EXPORT void ProcessTick(void)
{
    if (core_state > 0 && core_process_tick != NULL)
        core_process_tick();
}
