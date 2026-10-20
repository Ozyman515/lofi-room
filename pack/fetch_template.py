import sys, struct, zlib, urllib.request, ssl, os
url=sys.argv[1]; want=sys.argv[2:]
def get(rng=None):
    req=urllib.request.Request(url, headers={"Range":"bytes=%s"%rng} if rng else {})
    return urllib.request.urlopen(req, timeout=120)
r=get("0-0"); total=int(r.headers["Content-Range"].split("/")[1]); r.read(); print("size", total)
tail=get("%d-%d"%(total-66000,total-1)).read()
i=tail.rfind(b"PK\x06\x06")  # zip64 eocd
if i>=0:
    cd_size=struct.unpack("<Q",tail[i+40:i+48])[0]; cd_off=struct.unpack("<Q",tail[i+48:i+56])[0]
else:
    j=tail.rfind(b"PK\x05\x06"); cd_size,cd_off=struct.unpack("<II",tail[j+12:j+20])
cd=get("%d-%d"%(cd_off,cd_off+cd_size-1)).read()
p=0; entries={}
while p<len(cd) and cd[p:p+4]==b"PK\x01\x02":
    (ver,vn,flag,comp,mt,md,crc,csz,usz,nl,el,cl,dn,ia,ea,lho)=struct.unpack("<HHHHHHIIIHHHHHII",cd[p+4:p+46])
    name=cd[p+46:p+46+nl].decode(); extra=cd[p+46+nl:p+46+nl+el]
    if csz==0xFFFFFFFF or usz==0xFFFFFFFF or lho==0xFFFFFFFF:
        q=0
        while q<len(extra):
            hid,hsz=struct.unpack("<HH",extra[q:q+4]); d=extra[q+4:q+4+hsz]
            if hid==1:
                k=0
                if usz==0xFFFFFFFF: usz=struct.unpack("<Q",d[k:k+8])[0]; k+=8
                if csz==0xFFFFFFFF: csz=struct.unpack("<Q",d[k:k+8])[0]; k+=8
                if lho==0xFFFFFFFF: lho=struct.unpack("<Q",d[k:k+8])[0]; k+=8
            q+=4+hsz
    entries[name]=(comp,csz,usz,lho); p+=46+nl+el+cl
print(len(entries),"entries;", [n for n in entries if "windows" in n])
for w in want:
    comp,csz,usz,lho=entries[w]
    lh=get("%d-%d"%(lho,lho+29)).read(); nl,el=struct.unpack("<HH",lh[26:30])
    start=lho+30+nl+el
    data=get("%d-%d"%(start,start+csz-1)).read()
    if comp==8: data=zlib.decompress(data,-15)
    open(os.path.basename(w),"wb").write(data); print("got",w,len(data))
