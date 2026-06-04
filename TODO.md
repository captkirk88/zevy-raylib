### What to do...

- [x] Use `app` and the plugins add the systems in the correct stages and then we can remove the `gameLoop` function entirely and just call `app.run()` in `main`
- [ ] Refactor ui handling to not explicitly require calling the RelationsManager
    - Instead use OnAdded and OnRemoved system params in a system for when they are created we query for that UIContainer.
    - This will require all UI entities also have a UIContainer component that has the same name as the one we want to relate to.
    - Maybe implement UINode.init(.{ components... }) and then OnAdded(UINode) to handle that in a system...
- [x] fix TPS increasing when we have more entities