import Foundation

/// The JSON Schema written beside `config.json` as `config.schema.json`, so editors and agents can
/// check a change before saving it. `MacsPaneConfigFileTests` keeps it naming every field the file has.
public enum MacsPaneSchema {
    public static let text = #"""
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "MacsPane settings",
  "description": "MacsPane's settings file (mac++). MacsPane watches it: a change applies as soon as it is saved. A file that isn't JSON is left alone and the last good settings keep running. Every field is optional; a missing one takes its default. Check a file with: mac-plus-plus macspane check",
  "type": "object",
  "properties": {
    "$schema": { "type": "string" },
    "schemaVersion": { "type": "integer", "const": 1, "description": "The file's version. Leave it as it is." },
    "dwellMs": {
      "type": "integer", "minimum": 0, "default": 1000,
      "description": "How long, in milliseconds, a dragged window rests on the notch before the layout picker opens. The menu offers 300, 600, 1000 and 1500."
    },
    "setupCompleted": { "type": "boolean", "default": false, "description": "Whether first-time setup has been done; false shows it at launch." },
    "snap": {
      "type": "object",
      "description": "Dragging a window by its title bar to the notch.",
      "properties": {
        "enabled": { "type": "boolean", "default": true, "description": "The main switch: drag a window to the notch to snap it." },
        "showFullScreenPreview": { "type": "boolean", "default": true, "description": "Shade the box the window will fill while you aim." },
        "dragActivationDistance": { "type": "integer", "minimum": 0, "default": 8, "description": "Points the pointer must travel before a drag counts." },
        "titleBarBandHeight": { "type": "integer", "minimum": 0, "default": 44, "description": "Height in points of the band at a window's top that counts as its title bar." },
        "regions": { "type": "array", "description": "Not used any more; kept so older files read. Leave it out." }
      }
    },
    "windows": {
      "type": "object",
      "description": "Layouts: the shapes the notch picker offers and shortcuts send windows into.",
      "properties": {
        "enabled": { "type": "boolean", "default": true },
        "layouts": {
          "type": "array",
          "description": "Your own layouts. One with a built-in's id replaces that built-in. Built-ins (box numbers in brackets): halves [0 left, 1 right], twoThirds [0 left two thirds, 1 right third], fill [0], desk [0 left 60%, 1 top right, 2 bottom right], quarters [0 top left, 1 top right, 2 bottom left, 3 bottom right], thirds [0 left, 1 middle, 2 right], centre [0].",
          "items": { "$ref": "#/$defs/layout" }
        },
        "dragBarLayoutIDs": {
          "type": "array", "items": { "type": "string" },
          "default": ["halves", "twoThirds", "fill", "desk", "quarters"],
          "description": "The layouts the notch picker offers, by id, in order."
        },
        "layoutOrder": { "type": "array", "items": { "type": "string" }, "description": "The order the menu lists layouts in, by id. Empty: the default order." },
        "deletedBuiltIns": { "type": "array", "items": { "type": "string" }, "description": "Built-in layouts deleted from the menu, by id." },
        "drawGrid": { "type": "boolean", "default": true, "description": "Whether drawing a box in the editor snaps it to a grid." }
      }
    },
    "presets": {
      "type": "array",
      "description": "Presets: apps put in their places in one click from the menu (or a shortcut).",
      "items": { "$ref": "#/$defs/preset" }
    },
    "shortcuts": {
      "type": "array",
      "description": "Keys pressed anywhere that send the window in front to a layout's box, or apply a preset. One set of keys does one thing.",
      "items": { "$ref": "#/$defs/shortcut" }
    }
  },
  "$defs": {
    "keys": {
      "type": "string",
      "description": "Modifiers then a key, joined by +: ctrl, opt, shift, cmd, or hyper for all four; then a letter, digit, F1–F20, left, right, up, down, return, space, tab, escape, delete, home, end, pageup or pagedown. Needs ctrl, opt or cmd unless it's an F-key.",
      "examples": ["ctrl+opt+left", "ctrl+opt+return", "hyper+1", "F13"]
    },
    "region": {
      "description": "Where a box is: a zone's name, or a rectangle in fractions of the screen (origin bottom left, so y 0.5 height 0.5 is the top half).",
      "oneOf": [
        { "$ref": "#/$defs/zone" },
        {
          "type": "object",
          "properties": {
            "kind": { "const": "preset" },
            "zone": { "$ref": "#/$defs/zone" }
          },
          "required": ["kind", "zone"]
        },
        {
          "type": "object",
          "properties": {
            "kind": { "const": "custom" },
            "rect": {
              "type": "object",
              "properties": {
                "x": { "type": "number", "minimum": 0, "maximum": 1 },
                "y": { "type": "number", "minimum": 0, "maximum": 1 },
                "width": { "type": "number", "minimum": 0, "maximum": 1 },
                "height": { "type": "number", "minimum": 0, "maximum": 1 }
              },
              "required": ["x", "y", "width", "height"]
            }
          },
          "required": ["kind", "rect"]
        }
      ]
    },
    "zone": {
      "type": "string",
      "enum": ["maximize", "leftHalf", "rightHalf", "topHalf", "bottomHalf", "topLeftQuarter", "topRightQuarter", "bottomLeftQuarter", "bottomRightQuarter", "leftThird", "centerThird", "rightThird", "leftTwoThirds", "rightTwoThirds", "topThird", "middleThird", "bottomThird", "topTwoThirds", "bottomTwoThirds"]
    },
    "layout": {
      "type": "object",
      "properties": {
        "id": { "type": "string", "description": "Any id you like, such as \"sideBySide\"; shortcuts and dragBarLayoutIDs use it." },
        "name": { "type": "string" },
        "boxes": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/region" }, "description": "The boxes, numbered from 0 for shortcuts." },
        "boxLayers": { "type": "array", "items": { "type": "integer" }, "description": "Which box is in front where boxes overlap. Leave it out." }
      },
      "required": ["boxes"]
    },
    "preset": {
      "type": "object",
      "properties": {
        "id": { "type": "string", "description": "Any id you like, such as \"work\"; a shortcut names a preset by it." },
        "name": { "type": "string", "description": "As the menu lists it." },
        "slots": { "type": "array", "items": { "$ref": "#/$defs/slot" } },
        "layoutID": { "type": "string", "description": "The layout whose boxes this preset fills, if it came from one." },
        "cols": { "type": "integer", "minimum": 1, "default": 3, "description": "The editor's grid. Leave it out." },
        "rows": { "type": "integer", "minimum": 1, "default": 3, "description": "The editor's grid. Leave it out." },
        "profileID": { "type": "string", "description": "Not used. Leave it out." }
      },
      "required": ["id", "name", "slots"]
    },
    "slot": {
      "type": "object",
      "description": "One box of a preset and what goes in it.",
      "properties": {
        "region": { "$ref": "#/$defs/region" },
        "binding": {
          "type": "object",
          "description": "What fills the box: an app by bundle ID, the most recently used window not placed yet, or nothing.",
          "properties": {
            "kind": { "enum": ["app", "mostRecent", "empty"], "default": "mostRecent" },
            "bundleID": { "type": "string", "examples": ["com.apple.Safari", "com.microsoft.VSCode"] }
          }
        },
        "launchIfClosed": { "type": "boolean", "default": false, "description": "Open the app first if it isn't running." },
        "layer": { "type": "integer", "description": "Higher is in front where boxes overlap." },
        "isRemoved": { "type": "boolean", "default": false, "description": "A box of the preset's layout left out of this preset." },
        "id": { "type": "string", "description": "Leave it out; MacsPane makes one." }
      },
      "required": ["region"]
    },
    "shortcut": {
      "type": "object",
      "properties": {
        "keys": { "$ref": "#/$defs/keys" },
        "action": {
          "oneOf": [
            {
              "type": "object",
              "description": "Send the window in front to one box of a layout.",
              "properties": {
                "kind": { "const": "layoutBox" },
                "layoutID": { "type": "string", "examples": ["halves", "thirds", "fill"] },
                "box": { "type": "integer", "minimum": 0, "description": "The box's number, from 0." }
              },
              "required": ["kind", "layoutID", "box"]
            },
            {
              "type": "object",
              "description": "Apply a preset.",
              "properties": {
                "kind": { "const": "preset" },
                "id": { "type": "string", "description": "The preset's id." }
              },
              "required": ["kind", "id"]
            }
          ]
        },
        "isEnabled": { "type": "boolean", "default": true, "description": "false keeps the keys but lets them through to the app in front." }
      },
      "required": ["keys", "action"]
    }
  }
}
"""#
}
