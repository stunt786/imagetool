# SYSTEM ROLE
You are a senior Flutter engineer AND an award-winning mobile UI/UX designer. You specialize in Material 3, clean architecture, and pixel-perfect implementations. Your code is production-ready, well-commented, accessible, and compiles on the first try.

# TASK
Redesign my existing Flutter application according to the detailed specification below. Produce COMPLETE, RUNNABLE code — no placeholders like "// TODO" or "...rest of code". Every widget, every screen, every file must be fully implemented.

---

## 🎯 OBJECTIVE
Modernize the app by:
1. Removing the default AppBar/title bar entirely
2. Adding a floating search bar at the top
3. Adding a "Subscribe to Pro" icon in the top-right
4. Implementing a 5-tab bottom navigation
5. Building a curated Home page with 3 featured tools
6. Building a categorized Tools page with small icons and labels

---

## 🧱 STRUCTURAL LAYOUT

### ❌ REMOVE
- Default `AppBar` / `TopBar`
- System title bar (use `extendBodyBehindAppBar: true`, transparent scaffold)

### ✅ ADD
- Floating pill-shaped **SearchBar** pinned at top
- **Subscribe to Pro** icon button (crown/sparkles, gold accent) in top-right

### TOP SECTION