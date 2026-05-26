#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Standalone helper to run a command as root via Authorization Services.
// Usage: pm_helper <output_path>
// Runs "powermetrics --samplers smc -i 1 -n 1" and saves output to output_path.
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: pm_helper <output_path>\n");
        return 1;
    }

    const char *outputPath = argv[1];
    AuthorizationRef auth = NULL;
    OSStatus err;

    err = AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, &auth);
    if (err != errAuthorizationSuccess) {
        fprintf(stderr, "AuthorizationCreate failed: %d\n", (int)err);
        return 2;
    }

    AuthorizationItem item = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &item};
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                               kAuthorizationFlagPreAuthorize |
                               kAuthorizationFlagExtendRights;

    err = AuthorizationCopyRights(auth, &rights, NULL, flags, NULL);
    if (err != errAuthorizationSuccess) {
        fprintf(stderr, "AuthorizationCopyRights failed: %d\n", (int)err);
        AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
        return 3;
    }

    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "powermetrics --samplers smc -i 1 -n 1 > '%s' 2>&1", outputPath);

    char *args[] = {"-c", cmd, NULL};
    FILE *pipe = NULL;
    err = AuthorizationExecuteWithPrivileges(auth, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);

    if (err != errAuthorizationSuccess) {
        fprintf(stderr, "AuthorizationExecuteWithPrivileges failed: %d\n", (int)err);
        AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
        return 4;
    }

    if (pipe) {
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {}
        pclose(pipe);
    }

    usleep(200000);
    AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
    return 0;
}
