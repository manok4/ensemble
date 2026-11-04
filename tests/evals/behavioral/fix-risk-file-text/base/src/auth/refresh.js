exports.canRefresh = (refreshToken, now) => refreshToken.expiresAt <= now;
