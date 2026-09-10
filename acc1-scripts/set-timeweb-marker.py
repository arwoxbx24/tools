import glob, os
# Check existing markers
existing = glob.glob("/tmp/.project-context-read-timeweb-*")
print(f"Existing markers: {existing}")
# Create marker
marker = "/tmp/.project-context-read-timeweb-manual"
open(marker, 'w').close()
print(f"Created: {marker}")
existing2 = glob.glob("/tmp/.project-context-read-timeweb-*")
print(f"Markers after: {existing2}")
