# `data.gov.au` API Docs
The Australian Government doesn't seem too keen on writing documentation. To be fair, I wouldn't be either. However, they do seem to use [CKAN](https://ckan.org/), which does appear to be pretty easy to use.
## Quickstart
The base URL for the API is `https://data.gov.au/data/api/3/action`. Note the `/data` before `/api`. It's kind of weird but there's probably a good reason for it internally. If you're only here to find out why in the world your code broke all of a sudden, that's probably why.

After getting the base URL, it's pretty easy. The JSON returned should look something like:
```
{
    "help": "https://data.gov.au/data/api/3/action/help_show?$id",
    "error"?: {
        name: ["Error message"],
        "__type": "Error type",
    },
    "success": boolean,
    "result"?: {
        ...
    },
}
```

Note that, from what I've seen, either error or result will appear. The items are in order as they appear (from what I see at least).
