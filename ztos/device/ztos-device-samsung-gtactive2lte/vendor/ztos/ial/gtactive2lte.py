"""ztOSIAL backends for the Galaxy Tab Active2 (gtactive2lte, Exynos 7870),
for what the generic ones would get wrong on this tablet. Shape as in
ztos-device-samsung-starlte/vendor/ztos/ial/starlte.py.

Sleep: suspend to RAM is untested on mainline 7870 (no PMU sleep sequence, no
TMU/ACPM equivalent), so the system sleep targets are masked by layer.sh and
this backend says so instead of letting logind try. The screen still blanks
(ztMETRO's own timeout + panel DPMS). Remove this module and use
backend = "generic" in the manifest once `echo mem > /sys/power/state` comes
back reliably (s2idle at least).
"""
from ztos_ial.backends import NotSupported
from ztos_ial.backends import generic

# flip to True once suspend/resume is proven on this kernel (and unmask the targets)
SUSPEND_WORKS = False


class Sleep(generic.Sleep):
    interface = 'Sleep1'

    def props(self):
        base = super().props()
        if not SUSPEND_WORKS:
            base.update({'Method': 'none', 'Enabled': False, 'State': 'awake'})
        return base

    def m_SetEnabled(self, enabled):
        if not SUSPEND_WORKS:
            raise NotSupported('suspend is not validated on mainline Exynos 7870 yet')
        return super().m_SetEnabled(enabled)
