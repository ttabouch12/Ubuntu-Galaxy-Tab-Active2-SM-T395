#!/usr/bin/python3
# gta2srv: put apps on the external drive (the 500 GB share disk), used by gta2-dash /ctl (local only).
#   storage                      -> drive state + where Docker keeps its data
#   docker_move {to: drive|internal}   Docker / CasaOS apps: move Docker's data-root (detached job)
#   app_storage {id}             -> can this desktop app move? where is it now?
#   app_move {id, to: drive|internal}  apps that live in ONE folder (/opt/<x> or ~/<x>): move it, leave a symlink
# Debian packages (apt) spread files over /usr and cannot live on another disk: they are reported as not movable.
import json, os, re, shutil, subprocess, sys, time

SHARE = '/userdata/gta2srv/share'
DRIVE_APPS = SHARE + '/apps'
DRIVE_DOCKER = SHARE + '/docker'
DAEMON = '/etc/docker/daemon.json'
JOB = '/run/gta2/store-job.json'
UHOME = '/home/gta2'
NOMOVE = {'pi-apps', '.config', '.local', '.cache', 'mnt', 'Desktop', 'Downloads', 'Documents'}


def mounted():
    return os.path.ismount(SHARE)


def _free(p):
    try:
        s = os.statvfs(p); return s.f_bavail * s.f_frsize
    except OSError:
        return None


def docker_root():
    try: return json.load(open(DAEMON)).get('data-root', '/var/lib/docker')
    except Exception: return '/var/lib/docker'


def job_state():
    try: return json.load(open(JOB))
    except Exception: return {'state': 'idle'}


def _start_job(action, argv, what):
    if job_state().get('state') == 'running': return {'ok': False, 'error': 'another move is running'}
    os.makedirs(os.path.dirname(JOB), exist_ok=True)
    json.dump({'state': 'running', 'action': action, 'what': what, 'started': int(time.time())}, open(JOB, 'w'))
    subprocess.Popen(['systemd-run', '--quiet', '--collect', '--unit=gta2-store-job-%d' % int(time.time()),
                      '/usr/bin/python3', __file__, 'job'] + argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {'ok': True, 'job': 'started', 'what': what}


def app_folder(i):
    """the single folder a desktop app runs from, or (None, reason)"""
    sys.path.insert(0, '/usr/local/lib/gta2'); import gta2apps
    files = gta2apps._desktop_files()
    if i not in files: return None, 'unknown app'
    e = gta2apps._parse(files[i]) or {}
    tok = (e.get('Exec', '').split() or [''])[0].strip('"')
    if tok in ('env', 'sh', 'bash'): return None, 'started through a shell: cannot tell its folder'
    path = tok if tok.startswith('/') else shutil.which(tok) or ''
    if not path: return None, 'program not found'
    real = os.path.realpath(path)
    for base in ('/opt/', UHOME + '/', DRIVE_APPS + '/'):
        if real.startswith(base):
            top = real[len(base):].split('/')[0]
            if top in NOMOVE or not top: break
            if base == DRIVE_APPS + '/':   # already on the drive: find the symlink that points here
                for cand in ('/opt/' + top, UHOME + '/' + top):
                    if os.path.islink(cand) and os.path.realpath(cand) == DRIVE_APPS + '/' + top: return cand, None
                return None, 'on the drive but its link is missing'
            return base + top, None
    return None, 'installed as a system package (files spread over /usr): cannot move to another disk'


def ctl(a, v):
    v = v if isinstance(v, dict) else {}
    if a == 'storage':
        return {'ok': True, 'drive': mounted(), 'path': SHARE, 'free': _free(SHARE) if mounted() else None,
                'docker_root': docker_root(), 'docker_on_drive': docker_root().startswith(SHARE), 'job': job_state()}
    if a == 'store_job': return job_state()
    if a == 'docker_move':
        to = v.get('to')
        if to not in ('drive', 'internal'): return None
        if not mounted(): return {'ok': False, 'error': 'connect the external drive first'}
        src = docker_root(); dst = DRIVE_DOCKER if to == 'drive' else '/userdata/gta2srv/docker'
        if src == dst: return {'ok': False, 'error': 'already there'}
        return _start_job('docker_move', ['docker', src, dst], 'Docker apps -> ' + to)
    if a in ('app_storage', 'app_move'):
        i = v.get('id')
        if not isinstance(i, str) or not re.match(r'^[A-Za-z0-9._+-]{1,120}$', i): return None
        folder, why = app_folder(i)
        on = bool(folder) and os.path.islink(folder)
        if a == 'app_storage':
            return {'ok': True, 'movable': bool(folder), 'on_drive': on, 'folder': folder, 'reason': why, 'drive': mounted()}
        to = v.get('to')
        if to not in ('drive', 'internal') or not folder: return {'ok': False, 'error': why or 'bad request'}
        if not mounted(): return {'ok': False, 'error': 'connect the external drive first'}
        if (to == 'drive') == on: return {'ok': False, 'error': 'already there'}
        return _start_job('app_move', ['app', folder, to], os.path.basename(folder) + ' -> ' + to)
    return None


def _job(argv):
    """runs as its own systemd unit (root)"""
    log = []
    def run(c):
        r = subprocess.run(c, capture_output=True, text=True); log.append(' '.join(c) + ' -> %d' % r.returncode)
        if r.returncode: raise RuntimeError((r.stderr or r.stdout).strip()[-300:])
    try:
        if argv[0] == 'docker':
            src, dst = argv[1], argv[2]
            run(['systemctl', 'stop', 'docker.socket', 'docker', 'containerd'])
            os.makedirs(dst, exist_ok=True)
            run(['rsync', '-aHAX', '--delete', src.rstrip('/') + '/', dst + '/'])
            try: c = json.load(open(DAEMON))
            except Exception: c = {}
            c['data-root'] = dst; json.dump(c, open(DAEMON, 'w'), indent=2)
            run(['systemctl', 'start', 'containerd', 'docker'])
            log.append('old copy kept at ' + src + ' (delete it once everything works)')
        elif argv[0] == 'app':
            folder, to = argv[1], argv[2]; name = os.path.basename(folder)
            if to == 'drive':
                os.makedirs(DRIVE_APPS, exist_ok=True); dst = DRIVE_APPS + '/' + name
                run(['rsync', '-aHAX', folder + '/', dst + '/'])
                tmp = folder + '.gta2old'; os.rename(folder, tmp); os.symlink(dst, folder); shutil.rmtree(tmp)
            else:
                src = os.path.realpath(folder); tmp = folder + '.gta2new'
                run(['rsync', '-aHAX', src + '/', tmp + '/'])
                os.remove(folder); os.rename(tmp, folder); shutil.rmtree(src)
        st = {'state': 'done', 'ok': True}
    except Exception as e:
        st = {'state': 'done', 'ok': False, 'error': str(e)}
    st.update({'log': '\n'.join(log), 'finished': int(time.time())})
    old = job_state(); old.update(st); json.dump(old, open(JOB, 'w'))


if __name__ == '__main__' and len(sys.argv) > 2 and sys.argv[1] == 'job':
    _job(sys.argv[2:])
