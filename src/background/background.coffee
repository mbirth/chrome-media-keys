# Manage the currently playing tab id by keeping a stack of previous
# players so we can go back to previous tabs when new ones are closed
activeTabStack = []
activeTab = () -> activeTabStack[activeTabStack.length - 1]
chrome.tabs.onRemoved.addListener (tabId, removeInfo) ->
  index = activeTabStack.indexOf tabId
  if index != -1 then activeTabStack.splice index, 1

# Uniquely tag this install
if localStorage.getItem('installId') == null
  localStorage.setItem("installId", ''+(Math.floor(Math.random()*100000000000000)))
trackActivity = (eventName, attributes={}) ->
  attributes.installId = localStorage.getItem('installId')
  # Add keen tracking here

# Inject into all tabs to get immediate control of any playing services.
# We inject into every tab, not just the ones we know we support,
# in case someone has implemented the Shim API.
chrome.windows.getAll {populate: true}, (windows) ->
  for w in windows
    tabs = w.tabs
    for tab in tabs
      if tab.pinned then continue
      cb = () ->
        # Usually not an issue, just letting us know that it cannot script chrome: pages
        if chrome.runtime.lastError
          console.log("Last Error", chrome.runtime.lastError)
      chrome.tabs.executeScript tab.id, {file: 'content_scripts/content.js'}, cb


# Launch the option page on the first run
hasLaunchedOptions = localStorage.getItem("hasSeen2") # Has seen version of updates.  Increment every time there's something to alert
if not hasLaunchedOptions
  chrome.tabs.create {url: chrome.extension.getURL('options/options.html')}
  localStorage.setItem 'hasSeen2', true

# Request audio focus, telling the previously playing tab that it's lost
# focus and should pause itself.
requestFocus = (newFocusTab) ->
  newid = newFocusTab.id
  parser = document.createElement 'a' # Use anchor to parse urls
  parser.href = newFocusTab.url
  hostname = parser.hostname
  if activeTab() and activeTab() != newid
    chrome.tabs.sendRequest activeTab(), {action: 'lostFocus', hostname: hostname}, (()->)
  index = activeTabStack.indexOf newid
  if index != -1
    activeTabStack.splice index, 1
  activeTabStack.push newid

  useMediaKeys()
  window.plugin?.requestFocus()

window.sendAction = (action) ->
  if activeTab()
    chrome.tabs.sendRequest activeTab(), {action: action}, (()->)

wasPlaying = false
stateListeners = []
window.addStateListener = (l) ->
  stateListeners.push l

newState = (state) ->
  useMediaKeys() if not wasPlaying and state.playing
  wasPlaying = state.playing
  listener(state) for listener in stateListeners

handleRequestFromContentScript = (request, sender, sendResponse) ->
  console.log("REQ", request)
  # Todo: Add sending of tracks back here
  if request.action is 'newState' and sender.tab.id == activeTab()
    newState(request)
  else if request.action is 'requestFocus'
    requestFocus(sender.tab)
  else if request.action is 'injectController'
    script = findScriptByHost(request.host)
    if not script then return
    if script.indexOf('Shim') == -1
      trackController(request.host)
    chrome.tabs.executeScript sender.tab.id, {file: 'controllers/BasicController.js'}
    chrome.tabs.executeScript(sender.tab.id, {file: script})
    if request.host.indexOf("monstercat") > -1
      chrome.tabs.executeScript(sender.tab.id, {file: 'controllers/ShimController.js'})
    sendResponse()

handleRequestFromPopup = (request, sender, sendResponse) ->
  if request is 'focus'
    chrome.tabs.update activeTab(), {selected: true}
  else if request.action is 'getTabId'
    sendResponse({tabId: activeTab()})
  else # Pass the message to content script
    sendAction(request.action)

chrome.extension.onRequest.addListener (request, sender, sendResponse) ->
  if sender.tab and sender.tab.id != -1
    handleRequestFromContentScript request, sender, sendResponse
  else
    handleRequestFromPopup request, sender, sendResponse

chrome.tabs.onRemoved.addListener (tabId, removeInfo) ->
  if tabId is activeTab
    newState {playing: false, finished: true}
