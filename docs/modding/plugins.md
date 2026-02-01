# Server Plugins

Hytale server plugins are Java JARs that run on the server. The workflow generally includes a plugin manifest, a main entry point class, and packaging into a deployable JAR. The unofficial API reference (generated from the server JAR) is commonly used for discovery.

## Tooling Notes

- Plugin development uses Java 25 in current community docs.
- A plugin manifest (`manifest.json`) is required in the resources folder. The manifest fields and layout are documented in the plugin configuration docs.
- The Mod Tools GUI will generate a Gradle-based skeleton and leave placeholders for the server JAR dependency path.

## Sources

- Plugin development guide (Java 25 requirement)
  - https://hytalemodding.dev/en/docs/official-documentation/modding/plugin-development
- Plugin configuration / manifest documentation
  - https://hytale-dev.com/docs/hytale-server/plugin/configuration
- Unofficial API reference (generated from server JAR)
  - https://hytale-docs.dev
