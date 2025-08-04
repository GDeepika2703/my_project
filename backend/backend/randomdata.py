import pymysql
import time
from datetime import datetime
import random

# DB connection settings
conn = pymysql.connect(
    host='104.154.141.198',
    user='root',
    password='vistaarnksh',
    database='pro',
)
cursor = conn.cursor()

# Fetch all device IDs and their company names
cursor.execute("SELECT device_id, company_name FROM devices")
device_company_map = {row[0]: row[1] for row in cursor.fetchall()}
device_ids = list(device_company_map.keys())

if not device_ids:
    print("❌ No device_ids found in 'devices' table.")
    exit()

print("✅ Found device_ids:", device_ids)

# 🔧 Map each device to one of the 4 equipment names
equipment_names = ['Excavator', 'Crusher', 'Truck', 'Loader']
device_equipment_map = {
    device_id: equipment_names[i % len(equipment_names)]
    for i, device_id in enumerate(device_ids)
}

# Function to generate random sensor data
def generate_sensor_data(device_id, timestamp):
    
    return {
        "device_id": device_id,
        "company_name": device_company_map.get(device_id, "Unknown"),
        "timestamp": timestamp,
        "temperature": round(random.uniform(20, 40), 2),
        "dust": random.randint(50, 200),
        "air_quality": random.choice([random.randint(50, 150), None]),
        "co_ppm": random.randint(1, 5),
        "co2_ppm": random.randint(400, 800),
        "o2_percentage": round(random.uniform(19.0, 21.0), 2),
        "humidity": random.randint(30, 80),
        "water_level_m": round(random.uniform(0, 10), 2),
        "seismic_activity_hz": round(random.uniform(0.1, 3.0), 2),
        "noise_pollution_db": random.randint(60, 120),
        "pressure": round(random.uniform(900, 1100), 2),
        "gps_location": "12.9716,77.5946",
        "motor_load": round(random.uniform(0.2, 1.0), 2),
        "machine_runtime": random.randint(0, 10000),
        "fuel_consumption": round(random.uniform(1.0, 10.0), 2),
        "tyre_pressure": round(random.uniform(25.0, 35.0), 2),
        "battery_status": random.randint(0, 100),
        "load_weight": round(random.uniform(500.0, 3000.0), 2),
        "latitude": round(random.uniform(12.0, 13.0), 6),
        "longitude": round(random.uniform(77.0, 78.0), 6),
        "heart_rate": random.randint(60, 120),
        "gas_CO": round(random.uniform(0.1, 9.9), 2),
        "gas_CO2": round(random.uniform(300, 900), 2),
        "gas_NO2": round(random.uniform(0.01, 1.0), 2),
        "gas_H2S": round(random.uniform(0.01, 1.0), 2),
        "man_down_alert": random.choice([0, 1]),
        "equipment_name": device_equipment_map.get(device_id, "Unknown"),
        "active_blast_areas": round(random.uniform(10.0, 50.0), 2),
        "development_meters": round(random.uniform(10.0, 100.0), 2),
        "production_meters": round(random.uniform(50.0, 300.0), 2),
        "ore_mined": round(random.uniform(5.0, 50.0), 2),
        "throughput": round(random.uniform(50.0, 150.0), 2),
        "crusher_availability": round(random.uniform(70.0, 100.0), 2),
        "mill_vibration": round(random.uniform(20.0, 80.0), 2),
        "dump_trucks_utilization": round(random.uniform(60.0, 100.0), 2),
        "excavators_utilization": round(random.uniform(60.0, 100.0), 2),
        "drills_utilization": round(random.uniform(60.0, 100.0), 2),
        "utilization_percent": round(random.uniform(70.0, 100.0), 2),
        "exploration_cost": round(random.uniform(10000.0, 100000.0), 2),
        "higher_utilization": round(random.uniform(60.0, 100.0), 2),
        "completed_targets": random.randint(0, 10),
    }

# Make sure company_name column exists
cursor.execute("SHOW COLUMNS FROM sensor_data LIKE 'company_name'")
if not cursor.fetchone():
    cursor.execute("ALTER TABLE sensor_data ADD COLUMN company_name VARCHAR(255)")
    conn.commit()
    print("✅ Added 'company_name' column to sensor_data table.")

# Main loop to insert data every minute
while True:
    shared_timestamp = datetime.now().replace(second=0, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')

    for device_id in device_ids:
        data = generate_sensor_data(device_id, shared_timestamp)
        columns = ', '.join(data.keys())
        placeholders = ', '.join(['%s'] * len(data))
        values = list(data.values())

        sql = f"INSERT INTO sensor_data ({columns}) VALUES ({placeholders})"
        try:
            cursor.execute(sql, values)
            conn.commit()
            print(f"[{shared_timestamp}] ✅ Inserted data for device '{device_id}'")
        except Exception as e:
            print(f"❌ Error inserting for {device_id}: {e}")

    print("⏳ Waiting 60 seconds...\n")
    time.sleep(60)
