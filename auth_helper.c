#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Run a command as root via Authorization Services, capture output to a temp file
// Returns 0 on success, negative on error
int auth_run_command(const char *command, const char *outputPath) {
    static AuthorizationRef auth = NULL;
    OSStatus err;

    if (!auth) {
        err = AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, &auth);
        if (err != errAuthorizationSuccess) return -1;
    }

    AuthorizationItem item = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &item};
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                               kAuthorizationFlagPreAuthorize |
                               kAuthorizationFlagExtendRights;

    err = AuthorizationCopyRights(auth, &rights, NULL, flags, NULL);
    if (err != errAuthorizationSuccess) return -2;

    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "%s > '%s' 2>&1", command, outputPath);

    char *args[] = {"-c", cmd, NULL};
    FILE *pipe = NULL;
    err = AuthorizationExecuteWithPrivileges(auth, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);

    if (err != errAuthorizationSuccess) return -3;

    // Wait for output
    if (pipe) {
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {}
        pclose(pipe);
    }

    // Give the shell a moment to finish writing
    usleep(100000);
    return 0;
}
