import re


def slugify(title):
    """A title as a URL slug: lower case, words joined by single hyphens."""
    words = re.split(r"[^a-z0-9]", title.lower())
    return "-".join(words)
