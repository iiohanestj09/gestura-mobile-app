from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.firebase_auth import require_firebase_user, validate_session_id  # noqa: E402


def _request() -> SimpleNamespace:
    return SimpleNamespace(
        app=SimpleNamespace(
            state=SimpleNamespace(firebase_admin_app=object()),
        ),
    )


class FirebaseAuthTests(unittest.TestCase):
    def test_missing_bearer_token_is_rejected(self) -> None:
        with self.assertRaises(HTTPException) as error:
            require_firebase_user(_request(), None)

        self.assertEqual(error.exception.status_code, 401)

    @patch("app.firebase_auth.auth.verify_id_token")
    def test_verified_token_returns_uid_and_checks_revocation(
        self,
        verify_id_token: MagicMock,
    ) -> None:
        verify_id_token.return_value = {"uid": "user-123"}
        request = _request()
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="test-id-token",
        )

        uid = require_firebase_user(request, credentials)

        self.assertEqual(uid, "user-123")
        verify_id_token.assert_called_once_with(
            "test-id-token",
            app=request.app.state.firebase_admin_app,
            check_revoked=True,
        )

    @patch("app.firebase_auth.auth.verify_id_token", side_effect=ValueError("bad"))
    def test_invalid_token_is_reported_as_unauthorized(
        self,
        verify_id_token: MagicMock,
    ) -> None:
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="invalid-id-token",
        )

        with self.assertRaises(HTTPException) as error:
            require_firebase_user(_request(), credentials)

        self.assertEqual(error.exception.status_code, 401)

    def test_session_id_must_have_safe_characters_and_length(self) -> None:
        self.assertEqual(validate_session_id("a" * 24), "a" * 24)
        with self.assertRaises(HTTPException):
            validate_session_id("short")
        with self.assertRaises(HTTPException):
            validate_session_id("x" * 24 + "/")


if __name__ == "__main__":
    unittest.main()
