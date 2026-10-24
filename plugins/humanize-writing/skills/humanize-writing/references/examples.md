# One edit per genre

Each "after" adds nothing the "before" did not say. Check your own edits the same way. The businesses are invented.

## Personal post

Before:

> Big news from the Greenway team! 🌱
>
> Last month we wrapped up the new kitchen garden at Riverside Primary, and the kids have already harvested their first lettuces.
>
> Here's what the project taught us:
>
> **Kids are the best project managers.** The Year 4 class drew the bed layout, and we built it almost exactly as drawn.
>
> **Small beds, big impact.** Six raised beds now feed the school canteen once a week.
>
> **Partnerships matter.** Huge thanks to the Riverside P&C, who funded the timber and soil.
>
> Gardens aren't just about plants. They're about people.
>
> What's the best thing you've built with a community? 👇
>
> #Community #Gardening #Education #Sustainability #SmallBusiness

After:

> Last month the Greenway team wrapped up the new kitchen garden at Riverside Primary, and the kids have already harvested their first lettuces.
>
> The Year 4 class drew the bed layout, and we built it almost exactly as drawn. Six raised beds now feed the school canteen once a week.
>
> Thanks to the Riverside P&C, who funded the timber and soil.

## Email

Before:

> Hi Mei,
>
> I hope this email finds you well! I'm writing to give you a quick update on the bathroom renovation at your Coogee property.
>
> I know delays can be really frustrating, so I wanted to reach out as soon as possible. Unfortunately, the tiles you selected are back-ordered, and the supplier now expects them on 14 March. This means tiling will start on 17 March instead of 3 March, so the bathroom will be ready around 28 March rather than 14 March.
>
> If you'd prefer, we can switch to a similar in-stock tile and keep the original dates. Just let me know by Friday so we can lock things in.
>
> Please don't hesitate to reach out if you have any questions. We truly appreciate your patience and understanding!
>
> Warm regards,
> Dan

After:

> Hi Mei,
>
> The tiles you selected for the Coogee bathroom are back-ordered, and the supplier now expects them on 14 March. Tiling will start on 17 March instead of 3 March, so the bathroom will be ready around 28 March rather than 14 March.
>
> If you'd prefer, we can switch to a similar in-stock tile and keep the original dates. Could you let me know by Friday?
>
> Thanks for your patience.
>
> Dan

## Product page

Before:

> Meet Tidybooks. Bookkeeping, simplified.
>
> Tidybooks is the all-in-one bookkeeping app for Australian sole traders. Snap a photo of any receipt and Tidybooks reads the amount, date and GST for you, so you can spend less time on admin and more time doing what you love.
>
> No spreadsheets. No shoeboxes. No stress. Just clean books, ready for tax time.
>
> Smart and simple. Tidybooks connects to all major Australian banks and matches transactions automatically, giving you real-time visibility of your cash flow.
>
> Plans start at $12 a month. Try it free for 14 days.

After:

> Tidybooks is a bookkeeping app for Australian sole traders.
>
> Snap a photo of a receipt and Tidybooks reads the amount, date and GST. It connects to all major Australian banks and matches transactions automatically. You can see your cash flow in real time, and your books are ready for tax time without a spreadsheet.
>
> Plans start at $12 a month. Try it free for 14 days.

## Technical document

Before:

> ## Overview
>
> This document describes how to restore the staging database from a nightly backup.
>
> ## Steps
>
> 1. Confirm that no deploys are running on staging. This ensures a smooth and seamless restore process.
> 2. Run `./scripts/restore.sh --env staging --date YYYY-MM-DD`.
> 3. Wait for the script to print `Restore complete`. This typically takes around 10 minutes.
> 4. Run the smoke tests with `make smoke ENV=staging`.
>
> ## Notes
>
> Backups are kept for 14 days. It's important to note that restoring overwrites all data written to staging since the backup was taken.

After (two cuts; the structure, commands and every fact stay):

> ## Overview
>
> This document describes how to restore the staging database from a nightly backup.
>
> ## Steps
>
> 1. Confirm that no deploys are running on staging.
> 2. Run `./scripts/restore.sh --env staging --date YYYY-MM-DD`.
> 3. Wait for the script to print `Restore complete`. This typically takes around 10 minutes.
> 4. Run the smoke tests with `make smoke ENV=staging`.
>
> ## Notes
>
> Backups are kept for 14 days. Restoring overwrites all data written to staging since the backup was taken.

## Already clean

Before:

> Hi Jordan, the invoice for September is attached. It's $4,180, due on 15 October. Shout if anything looks off.

After: unchanged, with the note "Already reads cleanly; unchanged."
