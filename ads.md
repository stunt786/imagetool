### 1. The Ad Formats & Placements Breakdown

#### A. Rewarded Video Ads (Highest eCPM, Zero Annoyance)

Rewarded ads work best when framed as an **unlockable value** rather than a gate. Users willingly watch a 15–30s ad for a clear benefit.

* **Remove / Custom Watermark:**
* Trigger: On export modal for Image Resizer, Collage Builder, Document Scanner, and PDF Converter.
* UX: *"Watch a short video to export without watermark / with custom branding for this session."*


* **Batch Processing Access:**
* Free limit: Up to 3–5 items at once (e.g., resizing or converting 5 images).
* Batch limit bypass: *"Watch a video to batch process up to 50 files."*


* **Premium / Heavy Compute Features:**
* **OCR (PDF to TXT/DOCX)** and **Extreme PDF Compression** (isolate-based heavy lifting).
* **Magic Remove / Inpainting** in Document Scanner.
* UX: Give 1 free daily use, then require a rewarded video for subsequent uses.


* **High-DPI Export:**
* Allow 72–150 DPI for free; require a rewarded ad for 300 DPI high-res exports.



---

#### B. Interstitial Ads (Static / Short Video)

Interstitials yield steady revenue, but **never show them while the user is actively working** (e.g., cropping, selecting grid layouts, or reordering PDF pages). Only trigger them at **natural break points**.

* **Interaction-Based Frequency:**
* Implement an ad counter: Show an interstitial every **3 to 4 completed actions/exports**.
* **Critical:** Add a hard cooldown timer (minimum **60 to 90 seconds** between interstitials) so rapid actions don’t trigger back-to-back popups.


* **Natural Placements:**
* Immediately after tapping **"Export" / "Save"**, right before showing the "Success / Share / Open File" screen.
* When navigating back to the home screen after completing a workflow.


* **Important:** If a user just watched a **Rewarded Ad** (e.g., to remove a watermark), **suppress** the interstitial for that session. Never hit them with two full-screen ads in a row.

---

#### C. Native / Banner Ads (Consistent Baseline Revenue)

Banners are unobtrusive and monetize passive screen time.

* **Collapsible Banners (Adaptive Banners):**
* Place an **anchored adaptive banner** at the bottom of passive screens:
* `/pdfs` (My Files / Gallery)
* `/settings`


* *Avoid banners on screens where precise touches are required* (like the Collage Builder canvas, Crop/Rotate screen, or Camera preview).


* **Native In-Feed Ads:**
* Inside `/pdfs` (My Files): Insert a native ad card every 6–8 items inside the thumbnail grid/list. It blends seamlessly with the UI.



---

### 2. Feature-by-Feature Ad Strategy Matrix

| Feature / Screen | Primary Ad Type | Trigger & User Value Exchange |
| --- | --- | --- |
| **Image Resizer** | Rewarded + Counter Interstitial | Rewarded for batch processing (>5 images). Interstitial after export (counter-based). |
| **Collage Builder** | Rewarded Ad | Rewarded to unlock premium grid layouts or remove default watermark. |
| **Format Converter** | Rewarded Ad | Rewarded for batch converting >5 files or rare formats (HEIC/TIFF). |
| **Image to PDF / Merger / Splitter** | Interstitial | Shown after generating the final merged/split PDF file. |
| **Document Scanner** | Rewarded + Interstitial | Free filters; Rewarded ad for "Magic Remove (Inpainting)" & custom watermark removal. |
| **PDF Compressor** | Rewarded Ad | Low/Medium free; High/Extreme compression requires 1 rewarded ad. |
| **PDF Converter & OCR** | Rewarded Ad | PDF to TXT/DOCX (OCR) requires a rewarded video per document. |
| **My Files (`/pdfs`)** | Adaptive Banner / Native | In-feed native card in gallery + bottom adaptive banner. |
| **Settings** | Banner | Bottom banner + an entry point to "Remove Ads (Pro Upgrade)". |

---

### 3. Recommended Ad Networks & Mediation

To get the highest fill rates and eCPMs globally:

1. **Ad Mediation Engine:**
* **Google AdMob Mediation** or **AppLovin MAX**.
* Do not rely on a single ad network; mediation forces networks to bid in real-time (bidding auction) for the highest price per impression.


2. **Top Bidding Networks to Connect:**
* **Google AdMob / Google Ad Manager** (essential for utilities)
* **AppLovin** (strong fill rate & eCPM)
* **Meta Audience Network** (very strong native & interstitial demand)
* **Unity Ads / Mintegral** (good for rewarded video backfill)



---

### 4. Golden Rules for Utility Apps

* **Never block immediate core utility:** Let the user resize 1 image or merge 2 PDFs with minimal friction initially. If the first experience is blocked by an unskippable ad, churn will skyrocket.
* **Store "Unlocked" state temporarily:** If a user watches a rewarded ad to unlock batch mode or watermark removal, grant them a **session pass** (e.g., valid for 30 minutes or 3 exports) so they feel rewarded.
* **Offer a "Remove Ads / Lifetime Pro" IAP:** Users who use utility tools frequently hate ads. Offer a one-time purchase or low-cost subscription ($1.99–$4.99) to disable all ads, unlock all presets, and keep watermarks off permanently.