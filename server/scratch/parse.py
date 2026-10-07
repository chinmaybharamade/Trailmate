import json

with open('server/scratch/waypoint_output.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

route = data['routes'][0]
print("Has overview_polyline:", 'overview_polyline' in route)
if 'overview_polyline' in route:
    print("Overview length:", len(route['overview_polyline']))
print("Leg count:", len(route['legs']))
if len(route['legs']) > 1:
    print("Leg 0 has polyline:", 'polyline' in route['legs'][0])
    if 'polyline' in route['legs'][0]:
        print("Leg 0 polyline length:", len(route['legs'][0]['polyline']))
    print("Leg 1 has polyline:", 'polyline' in route['legs'][1])
    if 'polyline' in route['legs'][1]:
        print("Leg 1 polyline length:", len(route['legs'][1]['polyline']))
