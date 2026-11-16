import os
import unittest
import urllib.request


class ServiceTests(unittest.TestCase):
    """Talks to the staging service: needs SERVICE_TOKEN and the VPN."""

    def test_ping(self):
        token = os.environ["SERVICE_TOKEN"]
        request = urllib.request.Request("https://staging.internal.invalid/ping", headers={"Authorization": token})
        with urllib.request.urlopen(request, timeout=5) as reply:
            self.assertEqual(reply.status, 200)


if __name__ == "__main__":
    unittest.main()
