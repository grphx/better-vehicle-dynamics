"""Generate texture candidates with fal.ai (FLUX.1 [schnell], Apache-2.0) and record provenance.

    python3 tools/art/fal/fal_gen.py <name> "<prompt>" [--rembg] [--seed N]

Key: ~/.config/fal/key (never printed). Output: tools/art/fal/<name>.png, appended to PROVENANCE.md.
"""
import datetime
import json
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEY = (Path.home() / '.config/fal/key').read_text().strip()
MODEL = 'fal-ai/flux/schnell'


def call(model, payload):
    req = urllib.request.Request(f'https://fal.run/{model}', data=json.dumps(payload).encode(),
                                 headers={'Authorization': 'Key ' + KEY, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r)


def fetch(url, dst):
    with urllib.request.urlopen(url, timeout=120) as r:
        dst.write_bytes(r.read())


def main():
    name, prompt = sys.argv[1], sys.argv[2]
    rembg = '--rembg' in sys.argv
    payload = {'prompt': prompt, 'image_size': 'square', 'num_inference_steps': 4, 'num_images': 1,
               'enable_safety_checker': True}
    if '--seed' in sys.argv:
        payload['seed'] = int(sys.argv[sys.argv.index('--seed') + 1])
    out = call(MODEL, payload)
    url = out['images'][0]['url']
    seed = out.get('seed')
    used = [MODEL]
    if rembg:
        out2 = call('fal-ai/imageutils/rembg', {'image_url': url})
        url = out2['image']['url']
        used.append('fal-ai/imageutils/rembg')
    dst = HERE / f'{name}.png'
    fetch(url, dst)
    with open(HERE / 'PROVENANCE.md', 'a') as f:
        f.write(f'- `{name}.png`: {" + ".join(used)}, seed {seed}, {datetime.date.today()}. Prompt: "{prompt}"\n')
    print('wrote', dst)


main()
