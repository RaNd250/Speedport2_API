import ssl, re, json, hashlib, http.client, os, sys
from urllib.parse import quote

IP = os.environ.get('SP2_HOST', '192.168.1.1')
PW = hashlib.sha256(os.environ['SP2_PASS'].encode()).hexdigest().lower()
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
CK = {'Cookie': 'login_uid=0.5; username=admin'}

c = http.client.HTTPSConnection(IP, context=ctx, timeout=15)
c.request('GET', '/login.html', headers=CK)
T = re.search(r"csrf_token = '([0-9A-Z]+)'", c.getresponse().read().decode()).group(1)
c.request('POST', '/data/login.json?_=1&csrf_token=' + T,
          body='LoginName=admin&LoginPWD=' + PW,
          headers={**CK, 'Content-Type': 'application/x-www-form-urlencoded'})
r = c.getresponse()
r.read()
sid = [v for k, v in r.getheaders() if k.lower() == 'set-cookie'][0].split(';')[0]
H = {'Cookie': sid + '; login_uid=0.5; username=admin'}

names = [l.strip().split('/')[-1] for l in open('/root/fw-sp2/endpoints_list.txt') if l.strip()]
names = [n for n in names if n != 'data.cgi']

IMG = '/root/fw-sp2/imgdata'
stub, empty, static, live, err = [], [], [], [], []
for n in names:
    c.request('GET', '/data/' + quote(n) + '?_=2&csrf_token=' + T, headers=H)
    r = c.getresponse()
    d = r.read().decode('utf-8', 'replace')
    if r.status != 200:
        err.append((n, r.status))
        continue
    body = d.strip()
    if body in ('[ ]', '[]', ''):
        stub.append(n)
        continue
    fp = os.path.join(IMG, n)
    if os.path.exists(fp):
        a = re.sub(r'\s+', '', d)
        b = re.sub(r'\s+', '', open(fp, errors='replace').read())
        (static if a == b else live).append((n, len(d)))
    else:
        live.append((n, len(d)))

print('total endpoints probed:', len(names))
print('  stub  [ ] / empty :', len(stub))
print('  IDENTICAL to the firmware file (static template) :', len(static))
print('  DIFFERENT from the firmware file (=> live values) :', len(live))
print('  non-200 :', len(err))
print('\nLIVE-DIFFERING ENDPOINTS:')
for n, l in sorted(live, key=lambda x: -x[1]):
    print('  %-42s %6d' % (n, l))
print('\nNON-200:')
print('  ', ', '.join('%s(%d)' % e for e in err[:20]))
