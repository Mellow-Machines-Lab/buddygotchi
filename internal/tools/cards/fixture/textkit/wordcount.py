import sys
from collections import Counter


def count(text):
    return Counter(word.strip(".,!?;:").lower() for word in text.split() if word.strip(".,!?;:"))


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    text = open(argv[0]).read() if argv else sys.stdin.read()
    for word, n in count(text).most_common():
        print(f"{n}\t{word}")


if __name__ == "__main__":
    main()
