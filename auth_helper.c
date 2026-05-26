#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Debug log to stderr
#define AUTH_LOG(fmt, ...) fprintf(stderr, "[auth_helper] " fmt "\n", ##__VA_ARGS__)

// Run a command as root via Authorization Services, capture output to a temp file
// Returns 0 on success, negative on error
int auth_run_command(const char *command, const char *outputPath) {
    static AuthorizationRef auth = NULL;
    OSStatus err;

    if (!auth) {
        AUTH_LOG("AuthorizationCreate...");
        err = AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, &auth);
        if (err != errAuthorizationSuccess) {
            AUTH_LOG("AuthorizationCreate FAILED: %d", (int)err);
            return -1;
        }
        AUTH_LOG("AuthorizationCreate OK");
    }

    AuthorizationItem item = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &item};
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                               kAuthorizationFlagPreAuthorize |
                               kAuthorizationFlagExtendRights;

    AUTH_LOG("AuthorizationCopyRights...");
    err = AuthorizationCopyRights(auth, &rights, NULL, flags, NULL);
    if (err != errAuthorizationSuccess) {
        AUTH_LOG("AuthorizationCopyRights FAILED: %d", (int)err);
        return -2;
    }
    AUTH_LOG("AuthorizationCopyRights OK");

    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "%s > '%s' 2>&1", command, outputPath);

    char *args[] = {"-c", cmd, NULL};
    FILE *pipe = NULL;
    AUTH_LOG("AuthorizationExecuteWithPrivileges: %s", command);
    err = AuthorizationExecuteWithPrivileges(auth, "/bin/sh", kAuthorizationFlagDefaults, args, &pipe);

    if (err != errAuthorizationSuccess) {
        AUTH_LOG("AuthorizationExecuteWithPrivileges FAILED: %d", (int)err);
        return -3;
    }
    AUTH_LOG("AuthorizationExecuteWithPrivileges OK");

    // Wait for output
    if (pipe) {
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {}
        pclose(pipe);
    }

    // Give the shell a moment to finish writing
    usleep(100000);
    AUTH_LOG("Done, output at %s", outputPath);
    return 0;
}
