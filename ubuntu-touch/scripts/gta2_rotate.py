#!/usr/bin/python3
# gta2: rotate the system compositor (lomiri-system-compositor, Mir 1.8) output by 180 deg: display + touch, system-wide
import ctypes, sys, time
m = ctypes.CDLL('libmirclient.so.9') if False else None
for n in ('libmir1client.so.9', 'libmirclient.so.9'):
    try: m = ctypes.CDLL(n); break
    except OSError: pass
V = ctypes.c_void_p
m.mir_connect_sync.restype = V; m.mir_connect_sync.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
m.mir_connection_is_valid.argtypes = [V]; m.mir_connection_get_error_message.restype = ctypes.c_char_p; m.mir_connection_get_error_message.argtypes = [V]
m.mir_connection_create_display_configuration.restype = V; m.mir_connection_create_display_configuration.argtypes = [V]
m.mir_display_config_get_num_outputs.argtypes = [V]
m.mir_display_config_get_mutable_output.restype = V; m.mir_display_config_get_mutable_output.argtypes = [V, ctypes.c_size_t]
m.mir_output_get_orientation.argtypes = [V]; m.mir_output_set_orientation.argtypes = [V, ctypes.c_int]
m.mir_connection_preview_base_display_configuration.argtypes = [V, V, ctypes.c_int]
m.mir_connection_confirm_base_display_configuration.argtypes = [V, V]
m.mir_display_config_release.argtypes = [V]; m.mir_connection_release.argtypes = [V]
sock = (sys.argv[1] if len(sys.argv) > 1 else '/run/mir_socket').encode()
ang = int(sys.argv[2]) if len(sys.argv) > 2 else 180
for i in range(60):
    c = m.mir_connect_sync(sock, b'gta2-rotate')
    if c and m.mir_connection_is_valid(c): break
    if c: m.mir_connection_release(c)
    time.sleep(1)
else:
    print('connect failed'); sys.exit(1)
cfg = m.mir_connection_create_display_configuration(c)
for i in range(m.mir_display_config_get_num_outputs(cfg)):
    o = m.mir_display_config_get_mutable_output(cfg, i)
    print('output', i, 'orientation', m.mir_output_get_orientation(o), '->', ang)
    m.mir_output_set_orientation(o, ang)
m.mir_connection_preview_base_display_configuration(c, cfg, 10)
time.sleep(1)
m.mir_connection_confirm_base_display_configuration(c, cfg)
time.sleep(1)
print('err:', m.mir_connection_get_error_message(c))
m.mir_display_config_release(cfg); m.mir_connection_release(c)
