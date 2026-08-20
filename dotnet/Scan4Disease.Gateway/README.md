# Scan4Disease Gateway (.NET)

A thin **reverse-proxy + auth gateway** (ASP.NET Core + YARP) that sits in front of the
FastAPI backend. It changes nothing in `backend/`, `ml/`, or `app/`.

```
Flutter  ->  Gateway (:8080)  ->  FastAPI (:8000)
             validates JWT
             proxies everything
```

## What it does

- Forwards **every** request to FastAPI, unmodified.
- `/auth/*` and `/health` are open (login must work before you have a token).
- Everything else requires a valid JWT — the **same** token FastAPI issues, re-checked
  at the edge with the shared `JWT_SECRET`. The gateway never issues tokens itself.

## Run it

1. Use the **same** secret as the backend `.env`:

   ```powershell
   $env:JWT_SECRET = (Get-Content ../../.env | Select-String '^JWT_SECRET=').ToString().Split('=',2)[1]
   ```

   (or just `$env:JWT_SECRET = "the-same-long-secret"`)

2. Start the backend as usual (port 8000), then:

   ```bash
   dotnet run
   ```

3. Point the Flutter app's base URL at `http://<host>:8080` instead of `:8000`.

## Quick check

```bash
curl http://localhost:8080/health                 # 200 (open)
curl http://localhost:8080/auth/login -d ...       # 200 (open, proxied)
curl http://localhost:8080/predict                 # 401 without a Bearer token
curl -H "Authorization: Bearer <token>" http://localhost:8080/predict   # proxied
```

## Once it works

Rebind FastAPI to `127.0.0.1` so the gateway is the only public door — a config/env
change on the backend, no code change.
