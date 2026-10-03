# A Bangla guide for germanprobashe.com (#1246)

*agent-5, 2026-10-03. A guide for Bangladeshi students and job seekers that is useful without the app, written for German Probashe, BSAAG's sister magazine. BSAAG (124.8K members) bans promotion in the group, and its rule 8 asks members to write an article there and share it ([`channels.md`](../channels.md)). Sogda appears once, in a disclosed note at the end.*

**How it goes out:** the owner submits it through the magazine's contributor route (`ম্যাগাজিনে যোগ দিন`, https://www.germanprobashe.com/archives/10331), and the editors decide. Then, if it's published, the owner shares the article in BSAAG, as rule 8 invites. Nothing is sent by an agent.

**The facts:**
- **The visa rules are quoted from official pages** read on 2026-10-03: make-it-in-germany.com, the German Embassy Dhaka, BAMF and the Federal Foreign Office ([`research/2026-10-03-visa-german.md`](../research/2026-10-03-visa-german.md), with every quote). Where the law and the Dhaka embassy differ, the article says both.
- **The course's words and counts are tokens**, filled in Bangla digits when the article is sent:

```
python -c "import sys; sys.path.insert(0, 'tools/media'); import posts; print(posts.fill(open('docs/marketing/launch/germanprobashe-bn.md', encoding='utf-8').read().split('<!-- article -->')[-1], 'bn'))"
```

**Review:** *draft* until agent-1 reads the Bangla and the owner checks its nuance (bn is the owner's call), and agent-0 checks every fact against the research.

<!-- article -->

## ভিসার জন্য জার্মান: কোন কাজে কোন লেভেল, আর A1 থেকে B1 ধাপে ধাপে

জার্মানিতে পড়াশোনা, Ausbildung, চাকরি বা পরিবারের কাছে যাওয়ার প্রস্তুতি নিচ্ছেন? প্রথম প্রশ্নটা প্রায় সবার এক: কতটুকু জার্মান লাগবে? নিচের তথ্য ৩ অক্টোবর ২০২৬-এ জার্মান সরকারের ওয়েবসাইট (make-it-in-germany.com) আর ঢাকার জার্মান দূতাবাসের পাতা থেকে নেওয়া। নিয়ম বদলায়, তাই আবেদনের আগে দূতাবাসের পাতাটা আরেকবার দেখে নিন।

### ১. কোন ভিসায় কোন লেভেল

| উদ্দেশ্য | আইন কী বলে | ঢাকার দূতাবাস কী বলে |
|---|---|---|
| জার্মান ভাষায় পড়াশোনা | বিশ্ববিদ্যালয় যা চায়, সাধারণত B2 | ভিসার জন্য B1 (“ভালো” ফলসহ) সুপারিশ করে |
| ইংরেজিতে পড়াশোনা | সাধারণত জার্মান লাগে না | TOEFL বা IELTS চায় |
| ভাষা কোর্সের ভিসা | আইনে কোনো ন্যূনতম লেভেল নেই | Goethe-এর সনদ চায়, অন্তত B1 সুপারিশ করে; কোর্স সপ্তাহে অন্তত ১৮ ঘণ্টার হতে হবে |
| Ausbildung (পেশাগত প্রশিক্ষণ) | সাধারণত B1 | সাধারণত অন্তত A2, চিকিৎসা পেশায় অন্তত B1 |
| Chancenkarte (পয়েন্ট পদ্ধতি) | অন্তত জার্মান A1 বা ইংরেজি B2; জার্মানে A2-তে ১, B1-এ ২, B2 বা তার বেশিতে ৩ পয়েন্ট | Goethe-Institut-এর অন্তত A1 সনদ, এবং/অথবা অন্তত B2 ইংরেজির সনদ |
| দক্ষ কর্মী ও Blue Card | জার্মান বাধ্যতামূলক নয়; তবে স্বাস্থ্যখাতে (নার্স, ডাক্তার) রাজ্যভেদে B1 বা B2 লাগে | চেকলিস্টে ভাষার সনদ নেই |
| স্বামী বা স্ত্রীর কাছে যাওয়া | A1, তবে অনেক ক্ষেত্রে ছাড় আছে (যেমন স্বামী বা স্ত্রী Blue Card বা দক্ষ কর্মীর ভিসায় থাকলে) | ALTE মানের A1 সনদ, জার্মান নাগরিকের স্বামী বা স্ত্রীর জন্যও; দূতাবাস বলছে, বাংলাদেশে এখন শুধু Goethe-Institut এই সনদ দেয়। সঙ্গে আসা ১৬ থেকে ১৮ বছরের সন্তানের জন্য C1 |
| স্থায়ী বসবাস (Niederlassungserlaubnis) | সাধারণত B1; Blue Card-এ A1 থাকলে ২৭ মাস পর, B1 থাকলে ২১ মাস পর | — |
| নাগরিকত্ব | ৫ বছর পর, B1 | — |

মনে রাখবেন: আইন যা চায় না, দূতাবাস তা-ও চাইতে পারে, আবেদনটা বিশ্বাসযোগ্য দেখানোর জন্য। আর অপেক্ষা লম্বা: ঢাকার দূতাবাসের পাতায় লেখা, বৃত্তি ছাড়া ব্যাচেলর বা মাস্টার্সের ভিসায় অপেক্ষা এখন ২৭ মাসেরও বেশি, আর ভাষা কোর্সের ভিসায় এক বছরের বেশি। এই সময়টা জার্মান শেখার কাজে লাগানো যায়।

### ২. প্রতিটি লেভেলের পরীক্ষায় কী থাকে

Goethe-Zertifikat A1, A2 আর B1, তিনটিতেই চারটি অংশ: পড়া (Lesen), শোনা (Hören), লেখা (Schreiben) আর বলা (Sprechen)। Goethe-Institut-এর পাতা অনুযায়ী:
- **A1 (Start Deutsch 1):** ছোট নোটিশ, বিজ্ঞাপন আর সাইনবোর্ড পড়া; ছোট কথোপকথন, ফোনের বার্তা আর ঘোষণা শোনা; সহজ ফর্ম পূরণ আর নিজের সম্পর্কে ছোট লেখা; আর গ্রুপে নিজের পরিচয় দিয়ে দৈনন্দিন বিষয়ে প্রশ্নোত্তর।
- **A2:** ছোট খবর, ইমেইল আর ঘোষণা পড়া; দৈনন্দিন বিষয়ে বার্তা লেখা; আর নিজের জীবন নিয়ে কথা বলা, সঙ্গীর সঙ্গে কিছু ঠিক করা।
- **B1:** ব্লগ, ইমেইল আর খবর পড়ে মূল তথ্য ও মতামত বোঝা; ব্যক্তিগত ও আনুষ্ঠানিক ইমেইল আর নিজের মত জানিয়ে লেখা; জুটিতে আলোচনা আর একটি ছোট প্রেজেন্টেশন। চারটি মডিউল আলাদা আলাদা বা একসাথে দেওয়া যায়।

আসন আগেভাগে খুঁজুন: Goethe-Institut Bangladesh জানায়, মার্চ, জুন, সেপ্টেম্বর আর ডিসেম্বরের পরীক্ষায় তাদের নিজেদের ছাত্রছাত্রীরা আগে নিবন্ধন করতে পারে, তাই সাধারণের জন্য আসন কম থাকতে পারে।

### ৩. A1 থেকে B1: একটি সাপ্তাহিক পরিকল্পনা

প্রতিটি লেভেলে একই সপ্তাহ চলবে, শুধু বিষয় বদলাবে:

| দিন | কী করবেন |
|---|---|
| প্রতিদিন | কয়েকটি নতুন শব্দ, আর আগের শব্দগুলোর রিভিশন, ভুলে যাওয়ার ঠিক আগে। প্রতিটি বিশেষ্য শিখুন তার আর্টিকেলসহ (der, die বা das), কারণ পরে আলাদা করে মনে রাখা কঠিন। |
| শনিবার | সপ্তাহের ব্যাকরণ বিষয়টি পড়ুন, একটাই। |
| রবি থেকে বুধবার | সেই বিষয়ের ছোট অনুশীলন। আর কিছু বাক্য শুনে জোরে বলুন: উচ্চারণ শুরু থেকেই ঠিক করুন। |
| বৃহস্পতিবার | লেখা: A1-এ ফর্ম আর নিজের পরিচয়, A2-এ ছোট বার্তা ও ইমেইল, B1-এ নিজের মত জানিয়ে লেখা। |
| শুক্রবার | পরীক্ষার একটি অংশ সময় মেপে দিন, তারপর সপ্তাহের ভুলগুলো আবার দেখুন। |

পরীক্ষার আগের কয়েক সপ্তাহে পুরো মক পরীক্ষা দিন, চারটি অংশই, সময় মেপে।

কত সময় লাগে? Goethe-Institut-এর হিসাবে A1-এর জন্য ৮০ থেকে ২০০টি, A2-এর জন্য ২০০ থেকে ৩৫০টি, আর B1-এর জন্য ৩৫০ থেকে ৬৫০টি ৪৫-মিনিটের ক্লাস লাগে। তাই “কয়েক সপ্তাহে B1” জাতীয় প্রতিশ্রুতি এড়িয়ে চলুন। নিয়মিত রিভিশনই সবচেয়ে কাজে দেয়।

### ৪. জার্মানিতে প্রথম দিনগুলোর শব্দ

এই শব্দগুলো প্রথম সপ্তাহেই কাজে লাগে (উচ্চারণ বাংলা অক্ষরে):

- {featured.0.article} {featured.0.german}: {featured.0.meaning.bn} [{featured.0.guide.bn}]
- {featured.1.article} {featured.1.german}: {featured.1.meaning.bn} [{featured.1.guide.bn}]
- {featured.2.article} {featured.2.german}: {featured.2.meaning.bn} [{featured.2.guide.bn}]
- {featured.3.article} {featured.3.german}: {featured.3.meaning.bn} [{featured.3.guide.bn}]
- {featured.4.article} {featured.4.german}: {featured.4.meaning.bn} [{featured.4.guide.bn}]
- {featured.6.article} {featured.6.german}: {featured.6.meaning.bn} [{featured.6.guide.bn}]
- {featured.7.article} {featured.7.german}: {featured.7.meaning.bn} [{featured.7.guide.bn}]
- {featured.8.article} {featured.8.german}: {featured.8.meaning.bn} [{featured.8.guide.bn}]
- {featured.9.article} {featured.9.german}: {featured.9.meaning.bn} [{featured.9.guide.bn}]

### প্রকাশ

আমি Sogda তৈরি করি। এটি Android-এর জন্য একটি অফলাইন জার্মান কোর্স: A1 থেকে C2 পর্যন্ত {totals.steps}টি ধাপ, প্রতিটি শব্দের অর্থ বাংলায় আর উচ্চারণ বাংলা অক্ষরে, আর প্রতিটি ধাপে {totals.mock_exams_per_step}টি মক পরীক্ষা (Goethe বা telc-এর অফিসিয়াল প্রশ্নপত্র নয়)। ওপরের শব্দগুলো এর কোর্স থেকে নেওয়া। Google Play: <play-link germanprobashe/article> · https://www.sogda.de/bn/learn-german-in-bangla

### সূত্র (৩ অক্টোবর ২০২৬-এ দেখা)

- make-it-in-germany.com: ভিসা অনুযায়ী জার্মানের শর্ত, https://www.make-it-in-germany.com/en/living-in-germany/learn-german/knowledge
- ঢাকার জার্মান দূতাবাস:
  - পড়াশোনা: https://dhaka.diplo.de/bd-en/service/2685884-2685884
  - ভাষা কোর্স: https://dhaka.diplo.de/bd-en/service/2728870-2728870
  - Ausbildung: https://dhaka.diplo.de/bd-en/service/2685226-2685226
  - Chancenkarte: https://dhaka.diplo.de/bd-en/service/2685670-2685670
  - দক্ষ কর্মী ও Blue Card: https://dhaka.diplo.de/bd-en/service/2685666-2685666
  - পারিবারিক পুনর্মিলন: https://dhaka.diplo.de/bd-en/service/2685180-2685180
- স্থায়ী বসবাস: https://www.make-it-in-germany.com/en/visa-residence/living-permanently/settlement-permit
- নাগরিকত্ব: https://www.bamf.de/DE/Themen/Integration/ZugewanderteTeilnehmende/Einbuergerung/einbuergerung-node.html
- Goethe-Institut Bangladesh, পরীক্ষা: https://www.goethe.de/ins/bd/en/spr/prf/gzsd1/inf.html (A1), https://www.goethe.de/ins/bd/en/spr/prf/gzsd2/inf.html (A2), https://www.goethe.de/ins/bd/en/spr/prf/gzb1/inf.html (B1)
