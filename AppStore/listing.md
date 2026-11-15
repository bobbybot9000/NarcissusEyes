# LookNice — App Store Connect listing

Everything App Store Connect asks for, ready to paste. Limits are Apple's.

## App information

| Field | Value |
|---|---|
| Name (30) | `LookNice` |
| Subtitle (30) | `Meeting tool for narcissists` |
| Bundle ID | `com.bobbystrobeck.looknice` |
| SKU | `looknice-mac-1` |
| Primary language | English (U.S.) |
| Primary category | Utilities |
| Secondary category | Productivity |
| Content rights | Does not contain third-party content |
| Age rating | 4+ (answer "None" / "No" to every question) |

Backup subtitle if review objects to the joke: `A mirror under your webcam`

## Pricing and availability

- Price: **USD 0.99** (the lowest paid price point; other storefronts follow automatically)
- Availability: all countries, or all except the EU — see the DSA note in the checklist
- Requires the Paid Apps agreement, tax forms and a bank account to be active first

## Version 1.5.1

**Promotional text (170)**

> Look at yourself while looking like you're looking at them. A tiny mirror that sits right under your webcam.

**Description (4000)**

> LookNice puts a small live view of your own face right under your webcam.
>
> On a video call, everyone looks at themselves. The trouble is that your own picture is somewhere down the screen, so to everyone else you are staring at the floor. LookNice moves the thing you were going to look at anyway to the one spot where looking at it reads as eye contact.
>
> SITS UNDER THE CAMERA
> The mirror hugs the top of your screen. On a MacBook with a notch it docks directly beneath it, at the notch's exact width, so it looks like part of the hardware. Drag it along the top edge and it settles back into place.
>
> EYE-ONLY MODE
> Just the peepers. A slim band showing only your eyes, for when a whole face is too much face.
>
> TRANSPARENT MODE
> Fade the mirror down and read straight through it.
>
> KNOWS YOUR SETUP
> Plug in an external display or webcam and LookNice moves to it. Unplug and it comes home.
>
> STAYS OUT OF YOUR CALLS
> The mirror is excluded from screen sharing and screen recording. You see it. Nobody else ever does.
>
> PRIVATE BY CONSTRUCTION
> LookNice has no network access at all. Not switched off — not there. Your camera feed goes to your screen and nowhere else. Nothing is recorded, saved or sent. No account, no analytics, no ads.
>
> TINY
> Under 1 MB. Lives in the menu bar. Hide the mirror and the camera turns off completely.

**Keywords (100)**

`mirror,webcam,camera,eye contact,video call,meeting,notch,selfie,face,preview,eyeline,menu bar`

**URLs**

- Support URL: `https://look-nice.vercel.app/` — needs a way to contact you on the page first (see checklist)
- Marketing URL: `https://look-nice.vercel.app/`
- Privacy Policy URL: `https://look-nice.vercel.app/privacy.html`

**Copyright**: `2026 BobCo.`

**What's New** — not shown for a first release; leave empty.

## App Privacy

- Data collection: **No, we do not collect data from this app** → label reads "Data Not Collected"
- True by construction: the sandbox has no network entitlement.

## Export compliance

Already answered in the binary (`ITSAppUsesNonExemptEncryption = NO`). No questions will be asked.

## App Review information

**Sign-in required**: No

**Notes**

> LookNice is a menu bar utility, so it has no Dock icon and no main window. After launch, look for the eyes icon in the menu bar.
>
> On first launch it asks for camera access, which is its only permission. Once allowed, a small mirror of the camera appears at the top centre of the screen (directly under the notch on notched MacBooks). A Mac with a camera is needed to see it work.
>
> Hover over the mirror to show three controls: full face, eyes only, and transparent. The mirror can be dragged along the top edge of the screen.
>
> The mirror window is deliberately excluded from screenshots and screen sharing (NSWindow.sharingType = .none), so that it never appears in the user's video calls. This means it will not appear in screenshots or recordings taken during review; that is the intended behaviour, not a bug.
>
> Menu bar icon > Hide Mirror stops the camera. Menu bar icon > Quit LookNice quits.
>
> The app has no network access and collects no data.

## Screenshots

Required: at least one, 16:10 — 2880×1800, 2560×1600, 1440×900 or 1280×800.

The shipped app cannot be screenshotted, so use the capture build:

    Tools/screenshot_build.sh && open build/LookNice-Screenshots.app

Suggested set of three: mirror docked under the notch · eye-only mode · transparent mode over a document.
Use your own face. Not the stock photo from the website — third-party likeness is a rejection risk under guideline 5.2.
