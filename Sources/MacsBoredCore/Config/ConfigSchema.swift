import Foundation

/// The JSON Schema written beside `config.json` as `config.schema.json`, so editors and agents can
/// check a change before saving it. Kept in step with `ConfigFile` by `ConfigSchemaTests`.
public enum ConfigSchema {
    public static let text = #"""
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "MacsBored settings",
  "description": "MacsBored's settings file. MacsBored watches it: a valid change applies within a second; a file with a mistake is left alone, the last good settings keep running and the menu bar names the line. Fields MacsBored doesn't know are kept. Check a file with: mac-plus-plus macsbored check",
  "type": "object",
  "properties": {
    "$schema": {
      "type": "string"
    },
    "enabled": {
      "type": "boolean",
      "default": true,
      "description": "The main switch: all of MacsBored, passthrough and triggers alike."
    },
    "openAtLogin": {
      "type": "boolean",
      "description": "Open MacsBored when you log in. Leave it out to keep macOS's current setting."
    },
    "pauseKeys": {
      "oneOf": [
        {
          "$ref": "#/$defs/keys"
        },
        {
          "type": "null"
        }
      ],
      "default": "ctrl+opt+cmd+P",
      "description": "Pauses passthrough inside a passthrough app until you switch apps. null for none."
    },
    "capsLockAsHyper": {
      "type": "boolean",
      "default": false,
      "description": "Caps Lock holds ctrl+opt+shift+cmd (hyper), for triggers of your own."
    },
    "packs": {
      "type": "array",
      "description": "Actions grouped under a name, in the order the Actions list shows them. An action joins one with “pack”. A pack's switch turns its actions on and off together; its apps limit those of its actions that name no apps of their own.",
      "items": {
        "$ref": "#/$defs/pack"
      }
    },
    "passthrough": {
      "type": "array",
      "description": "Apps that get macOS's own shortcuts while they're in front: remote desktops and virtual machines. The first entry that fits wins.",
      "items": {
        "$ref": "#/$defs/passthrough"
      }
    },
    "triggers": {
      "type": "array",
      "description": "Keys of your own that do one thing.",
      "items": {
        "$ref": "#/$defs/trigger"
      }
    },
    "setupCompleted": {
      "type": "boolean",
      "default": false,
      "description": "Whether first-time setup has been done; false shows it at launch."
    }
  },
  "$defs": {
    "pack": {
      "type": "object",
      "required": [
        "name"
      ],
      "properties": {
        "name": {
          "type": "string",
          "minLength": 1,
          "description": "Its name; each pack's is its own."
        },
        "enabled": {
          "type": "boolean",
          "default": true,
          "description": "Off, none of its actions run."
        },
        "apps": {
          "type": "array",
          "description": "Its actions work only in these apps, by bundle ID; an action naming apps of its own keeps them. Empty or missing: everywhere.",
          "items": {
            "$ref": "#/$defs/app"
          }
        }
      }
    },
    "keys": {
      "type": "string",
      "description": "Keys as text: modifiers then the key, joined by +. Modifiers: ctrl, opt (or alt), shift, cmd, or hyper for all four. Keys: A–Z, 0–9, punctuation, space, tab, return, escape, delete, left, right, up, down, home, end, pageup, pagedown, F1–F20. The menu's symbols (⌃⌥⇧⌘) also work.",
      "examples": [
        "ctrl+opt+cmd+P",
        "hyper+N",
        "cmd+space",
        "shift+cmd+4",
        "F13"
      ]
    },
    "app": {
      "type": "string",
      "description": "An app by its bundle ID. Find one with: osascript -e 'id of app \"Notes\"'",
      "examples": [
        "com.microsoft.rdc.macos",
        "com.apple.Notes"
      ]
    },
    "condition": {
      "type": "object",
      "description": "One condition: {\"if\": kind} must hold, {\"unless\": kind} must not. windowTitleContains takes \"text\"; timeBetween takes \"from\" and \"to\" (a range past midnight wraps).",
      "properties": {
        "if": {
          "enum": [
            "fullScreen",
            "fillsScreen",
            "windowTitleContains",
            "externalDisplay",
            "onBattery",
            "timeBetween",
            "capsLock"
          ]
        },
        "unless": {
          "enum": [
            "fullScreen",
            "fillsScreen",
            "windowTitleContains",
            "externalDisplay",
            "onBattery",
            "timeBetween",
            "capsLock"
          ]
        },
        "text": {
          "type": "string"
        },
        "from": {
          "type": "string",
          "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$",
          "examples": [
            "09:00",
            "17:30"
          ]
        },
        "to": {
          "type": "string",
          "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$",
          "examples": [
            "09:00",
            "17:30"
          ]
        }
      },
      "oneOf": [
        {
          "required": [
            "if"
          ]
        },
        {
          "required": [
            "unless"
          ]
        }
      ],
      "examples": [
        {
          "if": "fullScreen"
        },
        {
          "unless": "onBattery"
        },
        {
          "if": "windowTitleContains",
          "text": "Prod"
        },
        {
          "if": "timeBetween",
          "from": "09:00",
          "to": "17:30"
        }
      ]
    },
    "when": {
      "description": "When it acts. A list means all of them must hold; {\"any\": [...]} means any one. Leave it out for always.",
      "oneOf": [
        {
          "type": "array",
          "items": {
            "$ref": "#/$defs/condition"
          }
        },
        {
          "type": "object",
          "properties": {
            "all": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/condition"
              }
            }
          },
          "required": [
            "all"
          ],
          "additionalProperties": false
        },
        {
          "type": "object",
          "properties": {
            "any": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/condition"
              }
            }
          },
          "required": [
            "any"
          ],
          "additionalProperties": false
        }
      ]
    },
    "action": {
      "type": "object",
      "description": "Exactly one of these.",
      "minProperties": 1,
      "maxProperties": 1,
      "properties": {
        "sendKeys": {
          "$ref": "#/$defs/keys",
          "description": "Press these keys instead."
        },
        "openApp": {
          "$ref": "#/$defs/app",
          "description": "Open this app, or bring it to the front."
        },
        "runShortcut": {
          "type": "string",
          "description": "Run the Shortcut with this name in Apple's Shortcuts app."
        },
        "passThrough": {
          "const": true,
          "description": "Send the trigger's own keys straight to the app in front, ahead of macOS and other apps' global shortcuts."
        },
        "open": {
          "type": "string",
          "description": "Open a link, or a file or folder (~/ works)."
        },
        "typeText": {
          "type": "string",
          "minLength": 1,
          "description": "Type this text into the app in front."
        },
        "wait": {
          "type": "number",
          "exclusiveMinimum": 0,
          "maximum": 3600,
          "description": "Wait this many seconds before the next step."
        },
        "runScript": {
          "oneOf": [
            {
              "type": "string",
              "minLength": 1
            },
            {
              "type": "object",
              "properties": {
                "shell": {
                  "type": "string",
                  "minLength": 1
                },
                "appleScript": {
                  "type": "string",
                  "minLength": 1
                }
              },
              "minProperties": 1,
              "maxProperties": 1,
              "additionalProperties": false
            }
          ],
          "description": "Run a shell script (zsh), or { appleScript: ... }; the next step waits for it to finish."
        },
        "moveWindow": {
          "enum": [
            "maximize",
            "leftHalf",
            "rightHalf",
            "topHalf",
            "bottomHalf",
            "topLeftQuarter",
            "topRightQuarter",
            "bottomLeftQuarter",
            "bottomRightQuarter",
            "leftThird",
            "centerThird",
            "rightThird",
            "leftTwoThirds",
            "rightTwoThirds"
          ],
          "description": "Move the window you're in to this part of its screen."
        },
        "applyPreset": {
          "type": "string",
          "minLength": 1,
          "description": "Arrange windows as this preset of the Windows tool does, by its ID."
        },
        "chooseMenuItem": {
          "oneOf": [
            {
              "type": "array",
              "minItems": 2,
              "items": {
                "type": "string",
                "minLength": 1
              }
            },
            {
              "type": "string",
              "minLength": 1
            }
          ],
          "description": "Choose an item from the app in front's menus, as clicking it would: the menu, any submenus, then the item, like [\"Format\", \"Column\", \"AutoFit Selection\"] or \"Format > Column > AutoFit Selection\". Case, and the dots after an item that opens a window, don't matter."
        }
      },
      "additionalProperties": false,
      "examples": [
        {
          "openApp": "com.apple.Notes"
        },
        {
          "runShortcut": "Start a Focus timer"
        },
        {
          "sendKeys": "cmd+left"
        },
        {
          "passThrough": true
        },
        {
          "open": "https://example.com"
        }
      ]
    },
    "passthrough": {
      "type": "object",
      "required": [
        "apps"
      ],
      "properties": {
        "name": {
          "type": "string",
          "description": "Defaults to the first app's name."
        },
        "pack": {
          "type": "string",
          "minLength": 1,
          "description": "The pack it's in, by name. A pack not in “packs” is made for it: on, and everywhere."
        },
        "enabled": {
          "type": "boolean",
          "default": true
        },
        "apps": {
          "type": "array",
          "minItems": 1,
          "items": {
            "$ref": "#/$defs/app"
          }
        },
        "shortcuts": {
          "description": "Which groups of macOS shortcuts the app gets, or \"all\". Defaults to every group but accessibility.",
          "oneOf": [
            {
              "type": "array",
              "items": {
                "enum": [
                  "appSwitcher",
                  "spotlight",
                  "missionControl",
                  "spaces",
                  "screenshots",
                  "inputSources",
                  "dockAndCentre",
                  "keyboardNavigation",
                  "accessibility",
                  "helpMenu"
                ]
              },
              "uniqueItems": true
            },
            {
              "const": "all"
            }
          ]
        },
        "sendEveryKey": {
          "type": "boolean",
          "default": false,
          "description": "Send every key straight to the app, ahead of other apps' global shortcuts (Raycast, Alfred, window managers)."
        },
        "modifiers": {
          "enum": [
            "asIs",
            "swapCommandControl"
          ],
          "default": "asIs",
          "description": "asIs: as the app maps them. swapCommandControl: cmd acts as Ctrl and ctrl as the Windows key."
        },
        "when": {
          "$ref": "#/$defs/when"
        }
      },
      "examples": [
        {
          "name": "Windows App",
          "apps": [
            "com.microsoft.rdc.macos"
          ],
          "shortcuts": [
            "appSwitcher",
            "spotlight",
            "missionControl",
            "spaces",
            "screenshots"
          ]
        }
      ]
    },
    "trigger": {
      "type": "object",
      "description": "An action: what starts it (any of keys, doubleTap, hold, sequence, mouseButton, appOpens, typed and at; keys when none is given), then one action or several steps.",
      "oneOf": [
        {
          "required": [
            "action"
          ]
        },
        {
          "required": [
            "steps"
          ]
        }
      ],
      "properties": {
        "name": {
          "type": "string"
        },
        "pack": {
          "type": "string",
          "minLength": 1,
          "description": "The pack it's in, by name. A pack not in “packs” is made for it: on, and everywhere."
        },
        "keys": {
          "oneOf": [
            {
              "$ref": "#/$defs/keys"
            },
            {
              "type": "array",
              "items": {
                "$ref": "#/$defs/keys"
              },
              "uniqueItems": true
            },
            {
              "type": "null"
            }
          ],
          "description": "The keys that set it off: one, or a list where any of them does. Each needs cmd, ctrl or opt (or an F-key). null: the trigger does nothing until it has keys.",
          "examples": [
            "ctrl+opt+N",
            [
              "cmd+space",
              "cmd+tab"
            ]
          ]
        },
        "enabled": {
          "type": "boolean",
          "default": true
        },
        "mouseButton": {
          "oneOf": [
            {
              "type": "integer",
              "minimum": 3
            },
            {
              "type": "array",
              "items": {
                "type": "integer",
                "minimum": 3
              }
            }
          ],
          "description": "Starts when this mouse button, or any in a list, is clicked: 3 is the middle, 4 and 5 the side buttons."
        },
        "appOpens": {
          "oneOf": [
            {
              "$ref": "#/$defs/app"
            },
            {
              "type": "array",
              "items": {
                "$ref": "#/$defs/app"
              }
            }
          ],
          "description": "Starts when this app, or any in a list, opens."
        },
        "typed": {
          "oneOf": [
            {
              "type": "string",
              "minLength": 2,
              "pattern": "^\\S+$"
            },
            {
              "type": "array",
              "items": {
                "type": "string",
                "minLength": 2,
                "pattern": "^\\S+$"
              }
            }
          ],
          "description": "Starts when these letters, or any in a list, are typed; they're taken out again."
        },
        "at": {
          "oneOf": [
            {
              "type": "string",
              "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"
            },
            {
              "type": "array",
              "items": {
                "type": "string",
                "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"
              }
            }
          ],
          "description": "Starts each day at this time, or each in a list, like \"09:00\"."
        },
        "doubleTap": {
          "oneOf": [
            {
              "enum": [
                "cmd",
                "opt",
                "ctrl",
                "shift"
              ]
            },
            {
              "type": "array",
              "items": {
                "enum": [
                  "cmd",
                  "opt",
                  "ctrl",
                  "shift"
                ]
              }
            }
          ],
          "description": "Starts when this modifier, or any in a list, is tapped twice quickly on its own."
        },
        "hold": {
          "oneOf": [
            {
              "$ref": "#/$defs/keys"
            },
            {
              "type": "array",
              "items": {
                "$ref": "#/$defs/keys"
              }
            }
          ],
          "description": "Starts when these keys, or any in a list, are held down a moment; let go sooner and they're pressed as usual. Each needs cmd, ctrl or opt (or an F-key)."
        },
        "sequence": {
          "oneOf": [
            {
              "type": "array",
              "minItems": 2,
              "items": {
                "$ref": "#/$defs/keys"
              }
            },
            {
              "type": "array",
              "items": {
                "type": "array",
                "minItems": 2,
                "items": {
                  "$ref": "#/$defs/keys"
                }
              }
            }
          ],
          "description": "Starts when these keys are pressed one after another, each within a second and a half, like [\"ctrl+a\", \"b\"]; several rows are a list of lists. The first needs cmd, ctrl or opt (or an F-key), or is a modifier tapped on its own: [\"opt\", \"h\", \"o\", \"i\"] starts with a tap of Option."
        },
        "action": {
          "$ref": "#/$defs/action"
        },
        "steps": {
          "type": "array",
          "minItems": 1,
          "items": {
            "$ref": "#/$defs/action"
          },
          "description": "Several actions, run in order."
        },
        "apps": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/app"
          },
          "description": "Only in these apps. Leave it out for everywhere except passthrough apps."
        },
        "when": {
          "$ref": "#/$defs/when"
        }
      },
      "examples": [
        {
          "name": "Open Notes",
          "keys": "ctrl+opt+N",
          "action": {
            "openApp": "com.apple.Notes"
          }
        },
        {
          "name": "Start work",
          "keys": "hyper+W",
          "steps": [
            {
              "openApp": "com.tinyspeck.slackmacgap"
            },
            {
              "wait": 0.5
            },
            {
              "openApp": "com.apple.mail"
            }
          ]
        },
        {
          "name": "Meeting mode",
          "appOpens": "us.zoom.xos",
          "action": {
            "runShortcut": "Meeting mode"
          }
        }
      ]
    }
  }
}
"""#
}
