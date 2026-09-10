#!/usr/bin/env python3
"""Smoke test for mojibake detection logic in validate-file-encoding.sh"""
import re
import tempfile
import os

def detect_mojibake(filepath):
    data = open(filepath, 'rb').read()
    count = data.count(b'\xc3\x90') + data.count(b'\xc3\x91')
    triple_c3 = len(re.findall(b'\xc3{3,}', data))
    total = len(data)
    if total > 20 and (count >= 3 or triple_c3 >= 1):
        return f"DETECTED: {count} mojibake byte-pairs, {triple_c3} triple-0xC3 clusters"
    return None

# Test 1: mojibake content (CP1251 re-encoded as Latin-1 then UTF-8)
f1 = tempfile.NamedTemporaryFile(suffix='.txt', delete=False)
f1.write(b'\xc3\x90' * 5 + b'\xc3\x91' * 5 + b'some padding to exceed 20 bytes')
f1.close()
result1 = detect_mojibake(f1.name)
os.unlink(f1.name)
assert result1 is not None, f"FAIL Test1: should detect mojibake, got None"
print(f"Test 1 PASS: {result1}")

# Test 2: clean UTF-8 Russian
f2 = tempfile.NamedTemporaryFile(suffix='.txt', delete=False)
f2.write("Привет мир, нормальный текст на русском языке".encode('utf-8'))
f2.close()
result2 = detect_mojibake(f2.name)
os.unlink(f2.name)
assert result2 is None, f"FAIL Test2: false positive on clean Russian: {result2}"
print(f"Test 2 PASS: clean UTF-8 not flagged")

# Test 3: triple 0xC3 cluster (Ã Ã Ã pattern from Latin-1 misread)
f3 = tempfile.NamedTemporaryFile(suffix='.txt', delete=False)
f3.write(b'some text \xc3\xc3\xc3more garbage content here extra bytes to exceed threshold')
f3.close()
result3 = detect_mojibake(f3.name)
os.unlink(f3.name)
assert result3 is not None, f"FAIL Test3: should detect triple-C3, got None"
print(f"Test 3 PASS: {result3}")

print("\nAll tests PASSED")
