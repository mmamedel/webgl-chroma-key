# Ultra Key - Use Case Document

## Document Purpose

This document provides practical use cases, workflows, and problem-solving scenarios for the Ultra Key effect in Adobe Premiere Pro, based on real-world training materials for sign language video editing.

---

## Primary Use Cases

### UC-1: Sign Language Video Production (Primary Use Case)

**Context:** Removing green screen backgrounds from sign language interpreter videos.

**Workflow:**

1. Apply Ultra Key effect to clip
2. Sample mid-tone green background with eyedropper (hold Ctrl/Cmd for 5x5 pixel sample)
3. Switch from Default to Aggressive preset
4. Evaluate using Alpha Channel mode (white = subject, black = background)
5. Make minimal adjustments if needed
6. Copy settings to all clips of same signer
7. Apply color correction

**Success Criteria:**

- Clean separation with no green edges/spill on hands
- No holes in signer's body
- Natural hair and edges
- Consistent results across all clips

**Key Insight:** "You will only need to do the process of Chroma Key once per signer. After color correction has been completed, the adjustments can be copied and then pasted to all the clips."

---

### UC-2: Batch Processing Multiple Clips

**Context:** Processing multiple clips of same subject under identical conditions.

**Workflow:**

1. Key first clip successfully
2. Complete color correction
3. Copy effects (Ctrl/Cmd + C)
4. Select all remaining clips
5. Paste effects (Ctrl/Cmd + V)
6. Spot-check for consistency

**Note:** Re-key only if recording conditions changed (lights moved, repositioned, new light added).

---

### UC-3: Challenging Footage with Uneven Lighting

**Context:** Green screen has shadows, wrinkles, or hot spots.

**Workflow:**

1. Try multiple eyedropper samples from different areas
2. Test Default vs Aggressive presets
3. Switch to Alpha Channel to identify gray problem areas
4. Adjust Matte Generation → Tolerance for color variation
5. Use Shadow slider for dark areas, Highlight for bright spots
6. Fine-tune Transparency if subject develops holes
7. Apply minimal Pedestal to clean semi-transparent pixels

**Key Technique:** Make small adjustments (5-10 points at a time) and verify in Alpha Channel after each change.

---

## Common Problem Scenarios

### Problem 1: Background Not Completely Removed

**Symptoms:** Semi-transparent gray areas in background (visible in Alpha Channel).

**Solutions (Priority Order):**

1. Switch to Aggressive preset
2. Resample key color from different area (try mid-tone close to subject)
3. Increase Tolerance (5-10 points at a time)
4. Adjust Shadow slider for dark background areas
5. Increase Pedestal slightly to convert gray to black

**Training Example:** "Notice what happens when this setting is changed [to Aggressive]. It is much better now. The signer is solid white and the background is almost completely black."

---

### Problem 2: Holes Appearing in Subject

**Symptoms:** See background through subject's body; gray/black holes in Alpha Channel.

**Root Cause:** Over-aggressive keying (Transparency or Shadow too high).

**Solutions:**

1. Decrease Transparency by 10-20 points
2. Undo last changes (Ctrl/Cmd + Z)
3. Reduce Shadow setting
4. Make smaller incremental adjustments

**Training Example:** "The shadow starts to disappear, but now this has opened up holes in the signer. If this stayed in the publication this way you would see part of the background through the signer's body."

**Critical Principle:** "It is important to make small adjustments when using any of these settings since they may correct one issue what cause another problem to appear."

---

### Problem 3: Green Spill on Hands/Edges

**Symptoms:** Green tint visible on skin, especially hands and fingers.

**Solutions (Sequential):**

1. Start with Spill Suppression → Spill slider
2. Increase until green shifts toward magenta
3. Adjust Range to control affected color spectrum
4. Add minimal Desaturate if needed (5-15 points)
5. Monitor for unnatural skin tones

**Training Example:** "In this example, there's a small amount of green that is appearing by the signer's fingers... Raising the number shifts the color from green to magenta so it starts to cancel out some of the tint."

**Warning:** "I don't want to take out too much color because it'll start to look unnatural very quickly."

---

### Problem 4: Harsh Artificial Edges

**Symptoms:** Visible outline, "cutout" appearance, hard edges.

**Solutions:**

1. Apply Soften (10-20 points) to blur edges
2. Reduce Choke if excessive (under 15)
3. Adjust Midpoint to lighten edges
4. Zoom to 100-200% to evaluate, then verify at full frame

**Training Warning:** "Using too much of this adjustment [Choke] will distort how the signer looks because it'll start to remove parts of his outline or his hands."

**Best Practice:** "All of the controls from matte cleanup can make very big changes and can distort how the signer appears, so only very small adjustments, if any, should be made."

---

### Problem 5: Poor Initial Key Result

**Symptoms:** Background mostly visible, subject partially transparent after first sample.

**Solutions:**

1. Resample immediately from different area
2. Use Ctrl/Cmd + click for 5x5 pixel sample (thicker eyedropper)
3. Sample mid-tone green (between light and dark)
4. Sample area close to subject
5. Try slightly darker shade

**Training Example:** "Notice what happens if I take the color from that darkest corner instead. So you can see that this definitely did not produce a good key."

**Key Insight:** "Selecting a good key color can reduce the number of changes that are needed."

---

## User Interaction Patterns

### Finding & Applying Ultra Key

**Method 1 (Navigation):**

- Effects panel → Video Effects → Keying → Ultra Key
- Drag to clip in timeline

**Method 2 (Search):**

- Type "Ultra Key" in Effects search bar
- Drag to clip in timeline

### Using the Eyedropper

**Standard Sample:**

- Click eyedropper icon → click background in Program Monitor

**Enhanced Sample (Recommended):**

- Click eyedropper → hold Ctrl/Cmd → click background
- Eyedropper becomes thicker (visual feedback)
- Samples 5x5 pixel area for more accurate color
- "Can sometimes help get a more accurate selection"

### Adjusting Parameters

**Method 1: Arrow Keys (Precise)**

- Click number → use Up/Down arrows
- Increments by 1
- "Good way to make small precise adjustments"

**Method 2: Click-Drag (Fast)**

- Click and hold number → drag left/right

**Method 3: Slider**

- Click dropdown arrow → expand slider → drag handle

**Method 4: Direct Input**

- Double-click number → type value → Enter

### Preset Behavior

**Selecting Aggressive:**

- All values automatically update
- Setting shows "Aggressive"

**Manual Adjustment:**

- Any parameter change switches to "Custom"
- "This helps you to see an adjustment has been made"

**Warning:** "If you were to switch back to the aggressive setting after making changes, those custom adjustments will be gone."

### Reset vs Undo

**Reset Arrow:**

- Returns to Default preset value
- Less commonly used in practice

**Undo (Preferred):**

- Ctrl/Cmd + Z
- "Instead of using this feature to reset the values, I'll use control Z"

---

## Quality Assessment Workflows

### Output Mode Evaluation Cycle

**Alpha Channel Mode:**

- **White** = Opaque subject (GOOD)
- **Black** = Transparent background (GOOD)
- **Gray** = Semi-transparent (PROBLEM)

**Status Mode:**

- **Black/White** = Ideal
- **Blue** = Acceptable
- **Yellow** = Marginal (needs attention)
- **Red** = Poor quality (must fix)

**Composite Mode:**

- Final visual appearance
- Check for spill, edges, natural integration

**Typical Pattern:** Make adjustment → Alpha Channel → Status → Composite → repeat

### Zoom Inspection for Edges

1. Program Monitor dropdown → select 100% or 200%
2. Evaluate edge quality up close
3. Make Matte Cleanup adjustments
4. Zoom back to Fit
5. Verify at full frame

**Quote:** "To help get a good look at this frame, use the drop down that appears to the left of the program monitor and select a percentage to zoom in for a closer look."

### Playback Quality Check

**Scrubbing:**

- Drag playhead through timeline
- Watch for consistency issues

**Full Playback:**

- Spacebar to play
- "Play through the entire clip to make sure everything looks good with the signer and the background"

---

## Workflow Templates

### Quick Key (High-Quality Footage)

**Duration:** 1-2 minutes

1. Apply Ultra Key
2. Sample mid-tone green (Ctrl/Cmd + click)
3. Switch to Aggressive
4. Verify in Alpha Channel
5. Done

---

### Standard Key (Typical Footage)

**Duration:** 3-5 minutes

1. Apply Ultra Key
2. Sample key color
3. Try Default, then Aggressive
4. Switch to Alpha Channel
5. Adjust Matte Generation as needed:
   - Transparency for overall balance
   - Shadow/Highlight for uneven lighting
   - Pedestal for cleanup
6. Switch to Composite
7. Address spill if visible
8. Playback to verify

---

### Problem-Solving Key (Difficult Footage)

**Duration:** 10-20 minutes

1. Apply Ultra Key
2. Try multiple eyedropper samples
3. Test presets
4. Use Status mode to identify problem areas
5. Systematically adjust Matte Generation
6. Check Alpha/Composite frequently
7. Use Undo liberally to compare
8. Address edge cleanup
9. Handle spill suppression
10. Consider garbage mattes for persistent issues
11. Final playthrough

---

## Best Practices from Training

### Sampling Strategy

- Sample mid-tone green (between light and dark)
- Sample close to subject
- Use Ctrl/Cmd + click for 5x5 pixel sample
- Try multiple samples if first doesn't work
- Avoid extreme dark or bright areas

### Adjustment Philosophy

- "Make small adjustments" (critical principle)
- Adjust 5-10 points at a time
- One parameter at a time
- Check Alpha Channel after each change
- Use Undo frequently

### Section Usage Priority

1. **Matte Generation** - Start here, affects entire image
2. **Matte Cleanup** - Use sparingly, can distort appearance
3. **Spill Suppression** - Only after base key is clean

### Matte Cleanup Caution

- "Can make very big changes and can distort how the signer appears"
- "Only very small adjustments, if any, should be made"
- Often Aggressive preset handles this automatically

### Spill Suppression Balance

- Start with Spill slider
- Be careful with Range (affects natural colors)
- Minimal Desaturate to avoid washed-out look
- Watch for overcorrection (magenta tint)

### Production Efficiency

- Key once per signer (if conditions consistent)
- Copy effects AFTER color correction complete
- Re-key only if lighting changes during session
- Document when conditions change

---

## Decision Trees

### Initial Key Decision Tree

```
Apply Ultra Key → Sample Key Color
│
├─ Good Result (solid white subject, black background)?
│  └─ YES → Done, proceed to next clip
│  └─ NO → Continue ↓
│
├─ Try Aggressive Preset
│  └─ Better?
│     ├─ YES → Done
│     └─ NO → Continue ↓
│
├─ Try Different Sample Location
│  └─ Better?
│     ├─ YES → Done or refine
│     └─ NO → Continue ↓
│
└─ Use Ctrl/Cmd + Click for 5x5 Sample
   └─ Better?
      ├─ YES → Done or refine
      └─ NO → Advanced adjustments needed
```

### Problem Diagnosis Tree

```
View in Alpha Channel
│
├─ Gray in Background?
│  └─ YES → Increase Transparency/Tolerance/Shadow
│
├─ Gray/Black in Subject?
│  └─ YES → Decrease Transparency/Shadow
│
├─ Green tint on subject (check Composite)?
│  └─ YES → Spill Suppression section
│
└─ Visible outline/harsh edges?
   └─ YES → Matte Cleanup (Soften primarily)
```

### When to Re-Key Decision

```
Pasting effects to new clip
│
├─ Same subject?
│  ├─ NO → Create new key
│  └─ YES → Continue ↓
│
├─ Same lighting setup?
│  ├─ NO → Create new key
│  └─ YES → Continue ↓
│
├─ Same background condition?
│  ├─ NO → Create new key
│  └─ YES → Use pasted effects
```

---

## Technical Integration Notes

### Effect Stack Order

**Typical Setup:**

1. Garbage matte (if needed) - above Ultra Key
2. **Ultra Key** - primary keying
3. Color correction effects - below Ultra Key
4. Background layer on track below

### Copy/Paste Behavior

- Copies ALL effects on clip
- Includes Ultra Key + color correction
- Preserves all parameter values
- Non-destructive to source clip

### Timeline Interaction

- FX button toggles effect on/off
- Undo works across timeline
- Can keyframe parameters (advanced use)
- Works on any video track

---

## Common Mistakes to Avoid

1. **Over-adjusting Matte Cleanup** - Can severely distort subject appearance
2. **Not checking Alpha Channel** - Makes informed adjustments impossible
3. **Sampling wrong area** - Dark corners or bright spots produce poor keys
4. **Making large adjustments** - Small increments prevent overcorrection
5. **Over-desaturating** - Causes unnatural washed-out appearance
6. **Forgetting to include color correction before copying** - Must copy complete effect stack
7. **Re-keying unnecessarily** - Use copied settings if conditions unchanged
8. **Not using Ctrl/Cmd + click** - Single pixel samples can be noisy

---

## Training Insights

### Most Important Quotes

**On Adjustment Philosophy:**

- "It is important to make small adjustments when using any of these settings since they may correct one issue what cause another problem to appear."

**On Matte Cleanup:**

- "All of the controls from matte cleanup can make very big changes and can distort how the signer appears, so only very small adjustments, if any, should be made."

**On Spill Suppression:**

- "I don't want to take out too much color because it'll start to look unnatural very quickly."

**On Batch Processing:**

- "You will only need to do the process of Chroma Key once per signer."

**On Footage Quality:**

- "A lot will depend on how the video clip was recorded. The better the recording, the fewer adjustments you will need to make."

**On Key Color Selection:**

- "Selecting a good key color can reduce the number of changes that are needed."

### Workflow Philosophy

The training emphasizes:

- Minimal intervention approach
- Systematic evaluation using output modes
- Small incremental adjustments
- Frequent quality checks
- Efficiency through batch processing
- Natural-looking results over technical perfection

---

## Success Metrics

### Technical Quality

- Solid white subject in Alpha Channel
- Solid black background in Alpha Channel
- No gray holes in subject
- Clean edges without harsh outlines
- No visible green/blue spill

### Production Efficiency

- One key per signer (under consistent conditions)
- 1-5 minutes per clip (depending on complexity)
- Successful batch application to multiple clips
- Minimal need for clip-specific adjustments

### Visual Quality

- Natural-looking integration with background
- Preserved fine detail (hair, fingers)
- Appropriate edge softness
- Natural skin tones
- No visible technical artifacts

---

## Conclusion

Ultra Key in production environments relies on:

1. **Good sampling technique** - Foundation of quality key
2. **Methodical evaluation** - Alpha/Status/Composite modes
3. **Restrained adjustment** - Small changes prevent overcorrection
4. **Batch efficiency** - Copy/paste for consistent subjects
5. **Natural results** - Technical perfection balanced with aesthetics

The training reveals that most professional work follows a simple pattern: sample well, use Aggressive preset, make minimal adjustments, copy to similar clips. Complex problem-solving is reserved for challenging footage, always with emphasis on incremental changes and frequent evaluation.
