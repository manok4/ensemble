# Bug: expired refresh tokens are accepted

`canRefresh` lets a user refresh a login session after the refresh token has expired, and refuses one that is still valid. The comparison is the wrong way round.
