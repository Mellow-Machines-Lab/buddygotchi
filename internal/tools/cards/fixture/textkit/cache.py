import time


class Cache:
    """A small cache with a size limit and a time to live.

    Reading an entry moves it to the fresh end; when the cache is full the
    entry at the stale end goes first. An entry older than `ttl` seconds is
    gone whenever it's next looked at.
    """

    def __init__(self, size=3, ttl=60, clock=time.monotonic):
        self.size, self.ttl, self.clock = size, ttl, clock
        self.entries = {}  # key -> (value, stored_at); dicts keep insertion order

    def get(self, key):
        hit = self.entries.pop(key, None)
        if hit is None:
            return None
        value, stored = hit
        if self.clock() - stored > self.ttl:
            return None
        self.entries[key] = (value, stored)  # back in at the fresh end
        return value

    def put(self, key, value):
        self.entries.pop(key, None)
        while len(self.entries) >= self.size:
            self.entries.pop(next(iter(self.entries)))  # the stale end
        self.entries[key] = (value, self.clock())
