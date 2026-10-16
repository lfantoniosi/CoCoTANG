# NRL English pronunciation rules

`eng_to_ipa.json`, `ipa_to_sp0256.json`, and `LICENSE` are from
[Greg Kennedy's p5-NRL-TextToPhoneme](https://github.com/greg-kennedy/p5-NRL-TextToPhoneme),
commit `f99c64ac84cf483b5ad51422e05277a3a383d869` (Unlicense).
The English rules originate in Elovitz et al.'s 1976 NRL letter-to-sound work.

`scripts/gen_ssc_tts.py` compiles these data into `src/audio/coco_ssc_tts_rom.v`.
The FPGA matcher implements left and right context, character classes, suffix
alternatives and backtracking repetition, then emits SP0256-AL2 allophones.
The generated pronunciation ROM uses 5,102 bytes. Regenerate it with:

```
python3 scripts/gen_ssc_tts.py
```

`python3 tests/ssc_psg/test_tts.py` compares the RTL output with an independent
Python regex implementation of the original rules across 250 phrases and
literal rule patterns. The test applies randomized output backpressure.
These pronunciation rules provide the SSC's ASCII/CR interface; they do not
reproduce the original TMS7040 firmware's exact pronunciations or timing.
