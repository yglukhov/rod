import json

type JsonSerializer* = ref object
    node*: JsonNode
