import struct,hashlib,sys
base,kern,ramd,dt,outp=sys.argv[1:6]
b=open(base,'rb').read(); K=open(kern,'rb').read(); R=open(ramd,'rb').read(); D=open(dt,'rb').read()
assert b[:8]==b'ANDROID!'
ps=struct.unpack('<I',b[36:40])[0]; al=lambda n:(n+ps-1)//ps*ps
h=bytearray(b[:ps]); struct.pack_into('<I',h,8,len(K)); struct.pack_into('<I',h,16,len(R)); struct.pack_into('<I',h,24,0); struct.pack_into('<I',h,40,len(D))
sh=hashlib.sha1()
for blob in (K,R,b'',D): sh.update(blob); sh.update(struct.pack('<I',len(blob)))
h[576:608]=sh.digest().ljust(32,b'\0')
pad=lambda x:x+b'\0'*(al(len(x))-len(x))
open(outp,'wb').write(bytes(h)+pad(K)+pad(R)+pad(D)+b'SEANDROIDENFORCE'); print('boot_ut',len(K),len(R),len(D))
