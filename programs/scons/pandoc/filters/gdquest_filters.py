
#!/usr/bin/env python3
import include
import link


def main(doc=None):
    doc = include.main(doc)
    doc = link.main(doc)
    return doc


if __name__ == "__main__":
    main()
