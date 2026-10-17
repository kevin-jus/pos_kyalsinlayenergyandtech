# Security server setup

The POS encrypts every cloud backup on the device before upload. This companion server stores only the encrypted envelope and provides branch/device license checks.

Start it with a long random administrator token:

```bash
POS_SERVER_ADMIN_TOKEN='replace-with-a-long-random-secret' PORT=8080 dart run bin/pos_security_server.dart
```

Deploy behind HTTPS. Keep the data file on an encrypted volume and restrict it to the service account. Create a branch with `POST /v1/admin/branches`, authenticated by the administrator token, using a unique `branchId` and 24+ character `apiToken`. Authorize each device with `POST /v1/admin/devices`. Enter the server URL, branch ID, and branch API token in **Security Center** on the POS.

The update endpoint is present for signed release metadata; distribute platform updates through your normal Android, desktop, or app-store signing pipeline. Do not let the POS download or execute arbitrary update URLs.
