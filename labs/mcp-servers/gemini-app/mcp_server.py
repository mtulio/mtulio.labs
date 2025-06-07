from flask import Flask, request, jsonify
import random
import time

app = Flask(__name__)

# --- Hypothetical Tool Implementations (Internal to MCP Server) ---
def get_weather_data(location: str):
    """Simulates fetching weather data for a given location."""
    print(f"[MCP Server] Getting weather for: {location}")
    time.sleep(1) # Simulate network delay
    if "error" in location.lower():
        return {"error": f"Could not fetch weather for '{location}'. Please be more specific or try again."}
    if "florianopolis" in location.lower():
        return {"location": location, "temperature": "25°C", "conditions": "Sunny", "humidity": "70%"}
    elif "sao paulo" in location.lower():
        return {"location": location, "temperature": "20°C", "conditions": "Partly Cloudy", "humidity": "85%"}
    else:
        return {"location": location, "temperature": f"{random.randint(10, 35)}°C", "conditions": random.choice(["Sunny", "Cloudy", "Rainy", "Windy"]), "humidity": f"{random.randint(50, 95)}%"}

def generate_random_hello_world():
    """Generates a random 'hello world' variant."""
    print("[MCP Server] Generating random hello world.")
    time.sleep(0.5) # Simulate slight delay
    variants = [
        "Hello, World!",
        "Greetings, Earthling!",
        "Hola Mundo!",
        "Bonjour le Monde!",
        "Ciao Mondo!",
        "こんにちは世界！",
        "مرحبا يا عالم!"
    ]
    return {"message": random.choice(variants)}

# --- MCP Server Endpoints ---
@app.route('/mcp/call_tool', methods=['POST'])
def call_tool():
    data = request.json
    tool_name = data.get('tool_name')
    tool_args = data.get('tool_args', {})

    print(f"[MCP Server] Received request to call tool: {tool_name} with args: {tool_args}")

    if tool_name == "get_weather":
        if 'location' not in tool_args:
            return jsonify({"error": "Missing 'location' argument for get_weather"}), 400
        result = get_weather_data(tool_args['location'])
        return jsonify(result)
    elif tool_name == "generate_random_hello_world":
        result = generate_random_hello_world()
        return jsonify(result)
    else:
        return jsonify({"error": f"Tool '{tool_name}' not found."}), 404

if __name__ == '__main__':
    print("--- Starting MCP Server ---")
    print("Available tools:")
    print("  - get_weather(location: str)")
    print("  - generate_random_hello_world()")
    print("Listening on http://127.0.0.1:5000/mcp/call_tool")
    import os
    debug_mode = os.getenv('FLASK_DEBUG', 'false').lower() == 'true'
    app.run(debug=debug_mode, port=5000)
