
import pycurl
import argparse
import sys
from tabulate import tabulate
import re

arg_parser = argparse.ArgumentParser()
arg_parser.add_argument("-url", type=str, required=True, help='CloudFront URL')
arg_parser.add_argument("-n", type=int, nargs='?', help='Number of requests')
args = arg_parser.parse_args()

url_format = re.compile("^https?://[a-zA-Z\d]+\.cloudfront\.net/?.?")
if not url_format.match(args.url):
    print("Use CloudFront URL in the following format: https://d1fpng8gomo4sk.cloudfront.net")
    sys.exit()
if not args.n:
    requests_total = 100
else:
    requests_total = args.n

try:
    from io import BytesIO
except ImportError:
    from StringIO import StringIO as BytesIO

buffer = BytesIO()
headers = {}
results = []
forbid_reuse = 1
reused_conns_count = 0
reused_conns_download_times = 0
new_conns_download_times = 0
url = args.url

def header_function(header_line):
    header_line = header_line.decode('iso-8859-1')

    if ':' not in header_line:
        return

    name, value = header_line.split(':', 1)
    name = name.strip()
    value = value.strip()
    name = name.lower()
    headers[name] = value

c = pycurl.Curl()
c.setopt(c.URL, url)
c.setopt(pycurl.WRITEFUNCTION, lambda x: None)
c.setopt(c.FORBID_REUSE, forbid_reuse)

c.setopt(c.WRITEFUNCTION, buffer.write)
c.setopt(c.HEADERFUNCTION, header_function)

for request_nr in range(0, requests_total):

    headers.clear()
    c.perform()

    # https://curl.se/libcurl/c/curl_easy_getinfo.html
    # TOTAL_TIME: the total time in seconds for the previous transfer, including name resolving, TCP connect etc. The double represents the time in seconds, including fractions.
    # NAMELOOKUP_TIME: the total time in seconds from the start until the name resolving was completed.
    # CONNECT_TIME: the total time in seconds from the start until the connection to the remote host (or proxy) was completed.
    # APPCONNECT_TIME:  the time, in seconds, it took from the start until the SSL/SSH connect/handshake to the remote host was completed
    # PRETRANSFER_TIME: the time, in seconds, it took from the start until the file transfer is just about to begin.
    # STARTTRANSFER_TIME: the time, in seconds, it took from the start until the first byte is received by libcurl. This includes CURLINFO_PRETRANSFER_TIME and also the time the server needs to calculate the result
    # CURLINFO_SPEED_DOWNLOAD, bytes/second
    # NUM_CONNECTS - how many new connections libcurl had to create to achieve the previous transfer
    # ACTIVESOCKET - the most recently active socket used for the transfer connection by this curl session. If the socket is no longer valid, CURL_SOCKET_BAD is returned.

    total_time = round(c.getinfo(pycurl.TOTAL_TIME) * 1000, 1)
    downstream_connect_time = round(c.getinfo(pycurl.CONNECT_TIME) * 1000, 1)
    namelookup_time = round(c.getinfo(pycurl.NAMELOOKUP_TIME) * 1000, 1)
    appconnect_time = round(c.getinfo(pycurl.APPCONNECT_TIME) * 1000, 1)
    # pretransfer_time = round(c.getinfo(pycurl.PRETRANSFER_TIME) * 1000, 1)
    starttransfer_time = round(c.getinfo(pycurl.PRETRANSFER_TIME) * 1000, 1)
    download_speed = round(c.getinfo(pycurl.SPEED_DOWNLOAD) /125000, 1) #Mbps
    # remote_ip = c.getinfo(pycurl.PRIMARY_IP)
    # local_port = c.getinfo(pycurl.LOCAL_PORT)

    if 'server-timing' in headers:
        timings_list = headers['server-timing'].split(',')
        for nr, item in enumerate(timings_list):
            if item == 'cdn-cache-miss' or item == 'cdn-cache-hit' or item == 'cdn-cache-refresh':
                timings_list[nr] = item + "=" + ';desc="true"'
        timings_dict = dict(s.split(';') for s in timings_list)
        for key, value in timings_dict.items():
            if key == 'cdn-downstream-fbl' or key == 'cdn-upstream-dns' or key == 'cdn-upstream-connect' or key == 'cdn-upstream-fbl':
                value = float(int(value.replace("dur=", "").replace("desc=", "")))
                if key == 'cdn-upstream-connect':
                    upstream_connect_time = value
                    if value == 0:
                        reused_conns_count += 1
                        reused_conns_download_times += total_time
                    else:
                        new_conns_download_times += total_time
                elif key == 'cdn-upstream-fbl':
                    origin_fbl = value
                elif key == 'cdn-downstream-fbl':
                    cf_fbl = value
    else:
        print("CloudFront Server-Timing headers are missing")
        sys.exit()

    request_nr += 1
    results.append([request_nr, total_time, namelookup_time, downstream_connect_time, appconnect_time, starttransfer_time,  upstream_connect_time, origin_fbl, cf_fbl, download_speed])


print(tabulate(
    results,
    tablefmt='grid',
    headers=["Request number", "Download time", "DNS resolution", "Downstream connect time", "Downstream TCP+SSL time", "User FBL", "Upstream TCP+SSL time", "Origin FBL", "CF FBL", "Download speed, Mbps"]
    )
)

reused_conns_download_times_avg = 'NA' if reused_conns_count == 0 else round(reused_conns_download_times / reused_conns_count)
new_conns_download_times_avg = 'NA' if requests_total - reused_conns_count == 0 else round (new_conns_download_times / (requests_total - reused_conns_count ))
latency_gain = 'NA' if new_conns_download_times_avg == 'NA' or reused_conns_download_times_avg == 'NA' else round(100 - reused_conns_download_times_avg / new_conns_download_times_avg * 100, 1)

print ("Total downstream connections:", requests_total )
print ("Number of re-used upstream connections:", reused_conns_count)
print ('Average download time for re-used upstream connections:', reused_conns_download_times_avg, "ms")
print ("Average download time for new upstream connections:", new_conns_download_times_avg, "ms")
print ("Latency gain:", latency_gain, "%")
