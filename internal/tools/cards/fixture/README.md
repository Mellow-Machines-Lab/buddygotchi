# textkit

A few small text helpers.

- `textkit.slug.slugify(title)`: a title as a URL slug.
- `textkit.cache.Cache`: a small cache with a size limit and a time to live.
- `python3 -m textkit.wordcount FILE`: how often each word appears.

Run the tests with `python3 -m unittest discover -s tests`.
Deploy a preview with `./deploy.sh`.
