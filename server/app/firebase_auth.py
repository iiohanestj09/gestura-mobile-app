from __future__ import annotations

import os
import re
from typing import Any

import firebase_admin
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth
from firebase_admin.exceptions import FirebaseError

_bearer_scheme = HTTPBearer(auto_error=False)
_SESSION_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{16,80}$")
_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "gestura-b095")


def initialize_firebase_admin() -> firebase_admin.App:
    try:
        return firebase_admin.get_app()
    except ValueError:
        return firebase_admin.initialize_app(
            options={"projectId": _PROJECT_ID},
        )


def validate_session_id(session_id: str) -> str:
    if not _SESSION_ID_PATTERN.fullmatch(session_id):
        raise HTTPException(
            status_code=422,
            detail="ID sesi real-time tidak valid.",
        )
    return session_id


def require_firebase_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Firebase ID token wajib disertakan.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    firebase_app: Any = getattr(request.app.state, "firebase_admin_app", None)
    if firebase_app is None:
        raise HTTPException(
            status_code=503,
            detail="Firebase Authentication belum siap pada backend.",
        )
    try:
        claims = auth.verify_id_token(
            credentials.credentials,
            app=firebase_app,
            check_revoked=True,
        )
    except (
        auth.InvalidIdTokenError,
        auth.ExpiredIdTokenError,
        auth.RevokedIdTokenError,
        auth.UserDisabledError,
        ValueError,
    ) as error:
        raise HTTPException(
            status_code=401,
            detail="Firebase ID token tidak valid atau kedaluwarsa. Login kembali.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from error
    except FirebaseError as error:
        raise HTTPException(
            status_code=503,
            detail=f"Firebase Authentication sementara gagal: {error}",
        ) from error

    uid = claims.get("uid")
    if not isinstance(uid, str) or not uid:
        raise HTTPException(
            status_code=401,
            detail="Firebase ID token tidak memiliki UID yang valid.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return uid
