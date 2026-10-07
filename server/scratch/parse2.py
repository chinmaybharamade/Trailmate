import json
import polyline

with open('server/scratch/waypoint_output.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

route = data['routes'][0]
pts = polyline.decode(route['overview_polyline'])
print("Total points:", len(pts))
print("Start:", pts[0])
print("End:", pts[-1])

print("Leg 0 start:", route['legs'][0]['start_location'])
print("Leg 0 end:", route['legs'][0]['end_location'])
print("Leg 1 start:", route['legs'][1]['start_location'])
print("Leg 1 end:", route['legs'][1]['end_location'])
