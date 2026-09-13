from ftplib import FTP
import json
from pathlib import Path

site = Path('/Users/ashleyrichards/development/ashleyrichards.tech')
config = json.loads((site / '.vscode/sftp.json').read_text())
files = [
    'index.html', 'pl/index.html', 'de/index.html', 'fr/index.html',
    'es/index.html', 'it/index.html', 'download/app_versions.json',
    'download/licences.json', 'admin_k2_8jH_d80/dashboard.php',
    'web_logos/a2.svg', 'app_shots/a2/shot1.png',
]

ftp = FTP()
ftp.connect(config['host'], int(config.get('port', 21)), timeout=30)
ftp.login(config['username'], config['password'])
ftp.cwd(config.get('remotePath', '/public_html'))

for relative in files:
    parts = relative.split('/')
    ftp.cwd(config.get('remotePath', '/public_html'))
    for folder in parts[:-1]:
        try:
            ftp.mkd(folder)
        except Exception:
            pass
        ftp.cwd(folder)
    with (site / relative).open('rb') as source:
        ftp.storbinary(f'STOR {parts[-1]}', source)
    print(f'Uploaded {relative}')

ftp.quit()
print(f'Hostinger deployment complete: {len(files)} files')
