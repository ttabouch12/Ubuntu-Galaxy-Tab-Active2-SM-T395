# Audio on the Galaxy Tab Active2 (SM-T395) with the mainline 6.18 kernel: plan

Status: research only. Nothing has been built or tested, and the tablet was not touched.
The vendor sources (GPL) are copied to `/home/claude/gta2ml/audio/vendor/` from
github.com/samsungexynos7870/android_kernel_samsung_exynos7870, branch `lineage-20`
(the tree the LineageOS 20 ROM uses). File/line numbers below refer to that branch.

## 1. Hardware: what the vendor kernel says

| Part | Chip / block | Where (vendor) | Bus |
|---|---|---|---|
| Codec (DAC/ADC, headphone, earpiece, **speaker driver**, mic bias, jack detect) | **COD3026X**, Samsung codec inside the PMIC package | `exynos7870-gtactive2lte_eur_open_04.dts:448-475` `cod3026x@04` | **hsi2c0 (0x10510000), 10-bit address 0x004**, same bus as the S2MPU05 PMIC (0x66) |
| Codec supply | S2MPU05 **LDO25** (`vdd_ldo25`, 0.8–2.375 V) | `eur_open_04.dts:366-372` | - |
| Codec IRQ / jack | GPA2-7 (`cod3026_irq`), ADC ch 2 (ear) and 4 (gdet) | `eur_open_04.dts:454-463`, `gtactive2_common.dtsi:737` | - |
| Speaker amplifier | **none external**: no TFA/MAX/CS35 node on gtactive2 (the A6 has a CS35L40, the tablet does not). The speaker is driven by the COD3026X SPK output | `gtactive2_common.dtsi:822-848` (`samsung,audio-amp` absent) | - |
| Audio mixer / interface | **AUDMIXER s1402x** @0x14880000 (DISPAUD), routes AP I2S to the PMIC codec pins | `exynos7870.dtsi:730-742`, `gtactive2_common.dtsi:102-110` (`bck-mcko-mode`) | APB |
| CPU DAI | **I2S0** `samsung,i2s-v5` @0x148A0000 (primary + secondary DAI), I2S1 @0x148B0000 (amp path, unused here) | `exynos7870.dtsi:744-790` | APB |
| DMA | **ADMA**: ARM **PL330** @0x14890000, irq 73, 4 channels, reset bit 3 of 0x148F1000 | `exynos7870.dtsi:797-811` | - |
| Audio subsystem glue | **LPASS/DISPAUD** @0x148F0000: AUD PLL, MI2S mux, soft resets `DISPAUD_CFG` (0x148F1000) bits 3 ADMA, 2 AMP, 1 MI2S, 0 MIXER; PMU pad retention `0x3028` bit 28 and `GPIO_MODE_AUD_SYS_PWR_REG` bit 0 | `sound/soc/samsung/lpass-exynos7870.c:66-71, 204-220, 252-307, 487-512` | - |
| Pins | gpz1-0..4 (I2S to PMIC), function 2, drv 5 | `gtactive2_common.dtsi:788-810` | - |
| Machine driver | `universal7870-cod3026.c` (1110 lines; ESA/EAX offload, CP/BT/FM dummies) | `sound/soc/samsung/` | - |

Vendor driver sizes: `cod3026x.c` 4314 lines, `exynos-audmixer-v2.c` 2747, `lpass-exynos7870.c` 870 (+ `lpass.c` 1337), machine 1110.

## 2. Mainline 6.18: what already exists

| Needed | In mainline 6.18? |
|---|---|
| CMU_DISPAUD clocks (AUD PLL, MI2S, MIXER, APB_AUD, APB_AUD_AMP, I2SCODCLKI) | **Yes**: `CLK_FOUT_DISPAUD_AUD_PLL`, `CLK_DOUT_DISPAUD_MI2S`, `CLK_DOUT_DISPAUD_MIXER`, `CLK_GOUT_DISPAUD_APB_AUD`, `CLK_GOUT_DISPAUD_APB_AUD_AMP`, `CLK_GOUT_DISPAUD_MI2S_AUD_I2SCODCLKI`, `CLK_GOUT_DISPAUD_MIXER_AUD_SYSCLK` (`include/dt-bindings/clock/samsung,exynos7870-cmu.h:147-190`) |
| Pinctrl for gpz1 (DISPAUD pin bank 0x148c0000) | **Yes** (`pinctrl_dispaud` in exynos7870.dtsi) |
| PL330 DMA driver | **Yes** (`drivers/dma/pl330.c`, generic `arm,pl330` node). The node itself is not in exynos7870.dtsi |
| Samsung I2S (v5-style, secondary DAI) | **Probably**: `sound/soc/samsung/i2s.c` has `samsung,exynos7-i2s` (Exynos7 = the same i2s-v5 IP generation). Needs register-level checking against the vendor `i2s.c` |
| hsi2c0 + S2MPU05 regulators (LDO25) | **Yes**, already used by our DT (`&hsi2c0 { pmic@66 }`) |
| **10-bit I2C addressing on hsi2c** | **No**: `i2c-exynos5.c` defines `HSI2C_10BIT_ADDR_MODE` (bit 30) but never uses it and does not advertise `I2C_FUNC_10BIT_ADDR`. Small patch needed (about 15 lines) |
| COD3026X codec driver | **No** (no `cod3026x` anywhere in mainline) |
| AUDMIXER s1402x driver | **No** |
| DISPAUD/LPASS glue (resets, PLL, pad retention) | **No** |
| Exynos7870 audio DT nodes (lpass, adma, i2s0/1, s1402x) | **No** |
| Upstream/postmarketOS work on 7870 audio | **None found.** The 6.18 7870 work is SoC/clocks/pinctrl/DSIM display (Kaustabh Chakraborty's series); the gitlab `exynos7870-mainline` patches are display/devices only. |

## 3. Plan (honest effort)

The path is not "enable a driver": three drivers must be ported from 3.18 and one I2C patch written.
Everything else (DMA, I2S, clocks, pins, regulator) is reusable.

1. **DT nodes** (draft in `audio-dt-draft.dtsi`): `adma` (pl330), `i2s0` (`samsung,exynos7-i2s`),
   `audmixer` (s1402x), the LPASS syscon block, the codec under `&hsi2c0` at `reg = <(0x04 | I2C_TEN_BIT_ADDRESS)>`,
   and a `simple-audio-card` (or audio-graph-card) linking i2s0 -> codec, with the mixer as an aux device.
   Half a day.
2. **i2c-exynos5: 10-bit address support** (set `HSI2C_10BIT_ADDR_MODE` in `HSI2C_ADDR` when
   `msg->flags & I2C_M_TEN`, advertise `I2C_FUNC_10BIT_ADDR`). Half a day + test (read the codec ID register).
3. **LPASS glue** as a tiny platform driver or folded into the mixer driver: enable AUD PLL (CCF does it),
   select the PLL path for MI2S, toggle the four soft resets in `DISPAUD_CFG`, release pad retention through
   the PMU syscon (`0x3028` bit 28, AUD `GPIO_MODE` bit 0). About 150 lines new code. 1 day.
   The DISPAUD power domain is shared with the display and is already on (we boot with it on), so no genpd is needed at first.
4. **AUDMIXER s1402x** port: keep only the AP-I2S-to-codec path (`bck-mcko-mode`), drop the BT/FM/CP paths.
   2747 -> about 500 lines, regmap-mmio, `snd_soc_component` API. 2–3 days.
5. **COD3026X** port: the biggest job. Port the 4314-line 3.18 driver to `snd_soc_component` +
   regmap-i2c (10-bit), keep the DAC -> HP / EP / **SPK** playback DAPM paths and the mic capture paths;
   drop the Samsung jack/water/ADC button detection first (add later via the IIO ADC). About 1500 lines. 4–6 days.
6. **Bring-up and tuning** on the tablet: clocks/rates (MI2S BCLK from AUD PLL 196.608 MHz), DMA microcode
   address (vendor puts PL330 microcode in SRAM `0x03002000`; mainline allocates it in DRAM, which normally works),
   reset polarity (unclear from the vendor source whether bit set = in reset), speaker volume/limiter registers,
   UCM/PipeWire profile for ztOS. 3–5 days, needs the tablet and someone listening.

**Total: about 2–3 weeks** of focused work for speaker + headphone playback, more for mic, jack detection and
earpiece. The first audible sound (a speaker test tone with `speaker-test`) is realistic after steps 1–5 plus
a couple of days of step 6, i.e. about 1.5–2 weeks.

**Shortcut that does NOT work:** reusing the vendor 3.18 driver as an out-of-tree module (the ASoC API changed
completely between 3.18 and 6.x).

## 4. Risks

* The codec registers are shared with nothing else, but the I2C bus is the PMIC's bus: a bad 10-bit
  transaction must not confuse the S2MPU05 (0x66). Test read-only first.
* DISPAUD is shared with the display (DECON clocks): resetting the wrong bit in `DISPAUD_CFG` can blank
  the screen. Bits 0–3 are audio only per the vendor header, but test over SSH.
* Speaker over-current: COD3026X has an internal speaker limiter (`COD3026X_5x_SPKLIMIT*`); the port must
  keep the vendor limiter init values.

## 5. Recommended next step

Do steps 1 + 2 + 3 as one small kernel build and test one thing: read the COD3026X ID/status register
over I2C (10-bit 0x004) from userspace with `i2ctransfer`, and check `DISPAUD_CFG` toggles cleanly.
If that works, the codec port (step 5) is worth starting; if the codec does not answer, we learn that
before spending a week on the port.
