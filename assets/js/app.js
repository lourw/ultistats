// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ultistats"
import topbar from "../vendor/topbar"

// Hide the top navbar while scrolling down; reveal it on any upward
// scroll. The hook also publishes a `--nav-offset` custom property on
// <html> so other sticky-headers (e.g. the live-game score header) can
// follow the navbar's visibility without a separate listener.
const NAV_HEIGHT = "3.5rem" // matches Tailwind h-14 on the navbar
const ScrollAwareNav = {
  mounted() {
    this._lastY = window.scrollY
    this._ticking = false
    this._setHidden(false)

    this._onScroll = () => {
      if (this._ticking) return
      this._ticking = true
      requestAnimationFrame(() => {
        const y = Math.max(window.scrollY, 0)
        const delta = y - this._lastY
        if (y <= 8) {
          this._setHidden(false)
        } else if (delta > 4) {
          this._setHidden(true)
        } else if (delta < -4) {
          this._setHidden(false)
        }
        this._lastY = y
        this._ticking = false
      })
    }
    window.addEventListener("scroll", this._onScroll, {passive: true})
  },
  destroyed() {
    window.removeEventListener("scroll", this._onScroll)
    document.documentElement.style.setProperty("--nav-offset", NAV_HEIGHT)
  },
  _setHidden(hidden) {
    if (this._hidden === hidden) return
    this._hidden = hidden
    this.el.classList.toggle("-translate-y-full", hidden)
    document.documentElement.style.setProperty(
      "--nav-offset",
      hidden ? "0px" : NAV_HEIGHT,
    )
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ScrollAwareNav},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

