#include <dirent.h>
#include <strings.h>

#include <Sources.h>

#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>

#include <Menes/ObjectHandle.h>

void Finish(const char *finish) {
    if (finish == NULL)
        return;

    const char *cydia(getenv("CYDIA"));
    if (cydia == NULL)
        return;

    int fd([[[[NSString stringWithUTF8String:cydia] componentsSeparatedByString:@" "] objectAtIndex:0] intValue]);

    FILE *fout(fdopen(fd, "w"));
    fprintf(fout, "finish:%s\n", finish);
    fclose(fout);
}

static void FixPermissions() {
    DIR *stash(opendir("/var/stash"));
    if (stash == NULL)
        return;

    while (dirent *entry = readdir(stash)) {
        const char *folder(entry->d_name);
        if (strlen(folder) != 8)
            continue;
        if (strncmp(folder, "_.", 2) != 0)
            continue;

        char path[1024];
        sprintf(path, "/var/stash/%s", folder);

        struct stat stat;
        if (lstat(path, &stat) == -1)
            continue;
        if (!S_ISDIR(stat.st_mode))
            continue;

        chmod(path, 0755);
    }

    closedir(stash);
}

#define APPLICATIONS "/Applications"
static bool FixApplications() {
    char target[1024];
    ssize_t length(readlink(APPLICATIONS, target, sizeof(target)));
    if (length == -1)
        return false;

    if (length >= sizeof(target)) // >= "just in case" (I'm nervous)
        return false;
    target[length] = '\0';

    if (strlen(target) != 30)
        return false;
    if (memcmp(target, "/var/stash/Applications.", 24) != 0)
        return false;
    if (strchr(target + 24, '/') != NULL)
        return false;

    struct stat stat;
    if (lstat(target, &stat) == -1)
        return false;
    if (!S_ISDIR(stat.st_mode))
        return false;

    char temp[] = "/var/stash/_.XXXXXX";
    if (mkdtemp(temp) == NULL)
        return false;

    if (false) undo: {
        unlink(temp);
        return false;
    }

    if (chmod(temp, 0755) == -1)
        goto undo;

    char destiny[strlen(temp) + 32];
    sprintf(destiny, "%s%s", temp, APPLICATIONS);

    if (unlink(APPLICATIONS) == -1)
        goto undo;

    if (rename(target, destiny) == -1) {
        if (symlink(target, APPLICATIONS) == -1)
            fprintf(stderr, "/Applications damaged -- DO NOT REBOOT\n");
        goto undo;
    } else {
        bool success;
        if (symlink(destiny, APPLICATIONS) != -1)
            success = true;
        else {
            fprintf(stderr, "/var/stash/Applications damaged -- DO NOT REBOOT\n");
            success = false;
        }

        // unneccessary, but feels better (I'm nervous)
        symlink(destiny, target);

        [@APPLICATIONS writeToFile:[NSString stringWithFormat:@"%s.lnk", temp] atomically:YES encoding:NSNonLossyASCIIStringEncoding error:NULL];
        return success;
    }
}

_H<NSMutableDictionary> Sources_;
bool Changed_;

_H<NSString> System_;

int main(int argc, const char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "configure") != 0)
        return 0;

    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    size_t size;
    sysctlbyname("kern.osversion", NULL, &size, NULL, 0);
    char *osversion = new char[size];
    if (sysctlbyname("kern.osversion", osversion, &size, NULL, 0) != -1)
        System_ = [NSString stringWithUTF8String:osversion];

    NSDictionary *metadata([[[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"] autorelease]);
    NSUInteger version(0);

    if (metadata != nil) {
        Sources_ = [metadata objectForKey:@"Sources"];

        if (NSNumber *number = [metadata objectForKey:@"Version"])
            version = [number unsignedIntValue];
    }

    if (Sources_ == nil)
        Sources_ = [NSMutableDictionary dictionaryWithCapacity:8];

    if (version == 0) {
        CydiaAddSource(@"http://apt.thebigboss.org/repofiles/cydia/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://apt.modmyi.com/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://cydia.zodttd.com/repo/cydia/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://repo666.ultrasn0w.com/", @"./");
    }

    CydiaWriteSources();

    FixPermissions();

    if (FixApplications())
        Finish("restart");

    [pool release];
    return 0;
}
