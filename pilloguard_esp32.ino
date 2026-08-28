/*
 * ============================================================
 *                    PilloGuard ESP32
 * ============================================================
 *
 * Hardware:
 *  - ESP32 / MYOSA Mini Kit
 *  - MPU6050
 *  - SSD1306 OLED
 *  - BMP180
 *  - APDS9960
 *  - 3 x 0-40 kPa Bladder Pressure Sensors
 *  - 3 x Pneumatic Actuators / Pumps
 *  - BLE communication with Flutter App
 *
 * Architecture:
 *
 *       Sensors
 *          |
 *          v
 *       ESP32
 *       /   \
 *      /     \
 *     v       v
 *   OLED     BLE ---> Flutter App
 *                    |
 *                    v
 *               AI / Decision
 *                    |
 *              LEFT/CENTER/RIGHT
 *                    |
 *                    v
 *                  BLE
 *                    |
 *                    v
 *                  ESP32
 *                    |
 *             +------+------+------+
 *             |      |      |
 *           LEFT   CENTER  RIGHT
 *          bladder bladder bladder
 *
 * Pressure feedback ALWAYS remains local to ESP32.
 *
 * ============================================================
 */

#include <Wire.h>
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// MYOSA sensors
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BMP085.h>
#include <Adafruit_APDS9960.h>

// OLED
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>


// ============================================================
//                    GPIO CONFIGURATION
// ============================================================
//
// IMPORTANT:
// Replace these with the ACTUAL wiring of your hardware.
// Do NOT guess these values.
//

#define I2C_SDA              21
#define I2C_SCL              22

#define PUMP_LEFT_PIN        25
#define PUMP_CENTER_PIN      26
#define PUMP_RIGHT_PIN       27

#define VALVE_LEFT_PIN       32
#define VALVE_CENTER_PIN     33
#define VALVE_RIGHT_PIN      14


// ============================================================
//                PRESSURE SENSOR INPUTS
// ============================================================
//
// These are intentionally configurable.
//
// Your 0-40 kPa pressure modules must be connected according
// to their actual output interface.
//
// If your exact modules provide analog output:
//
//      LEFT   -> ADC
//      CENTER -> ADC
//      RIGHT  -> ADC
//
// Change these pins to your actual ADC wiring.
//

#define PRESSURE_LEFT_PIN       34
#define PRESSURE_CENTER_PIN     35
#define PRESSURE_RIGHT_PIN      36


// ============================================================
//                         OLED
// ============================================================

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

Adafruit_SSD1306 display(
    SCREEN_WIDTH,
    SCREEN_HEIGHT,
    &Wire,
    -1
);


// ============================================================
//                       SENSORS
// ============================================================

Adafruit_MPU6050 mpu;
Adafruit_BMP085 bmp;
Adafruit_APDS9960 apds;


// ============================================================
//                    SYSTEM VARIABLES
// ============================================================

float leftPressure = 0.0;
float centerPressure = 0.0;
float rightPressure = 0.0;

float temperature = 0.0;
float atmosphericPressure = 0.0;

float accelX = 0.0;
float accelY = 0.0;
float accelZ = 0.0;

float gyroX = 0.0;
float gyroY = 0.0;
float gyroZ = 0.0;

uint16_t proximity = 0;

bool gestureDetected = false;

bool bleConnected = false;


// ============================================================
//                  BLADDER CONFIGURATION
// ============================================================

enum Bladder
{
    NONE,
    LEFT,
    CENTER,
    RIGHT
};

Bladder activeBladder = NONE;


// Target and safety pressure.
// These MUST be calibrated experimentally for your bladder.

float TARGET_PRESSURE = 8.0;      // example only
float SAFETY_PRESSURE = 12.0;     // example only


// ============================================================
//                    BLE CONFIGURATION
// ============================================================

#define SERVICE_UUID \
"4fafc201-1fb5-459e-8fcc-c5c9c331914b"

#define TELEMETRY_UUID \
"beb5483e-36e1-4688-b7f5-ea07361b26a8"

#define COMMAND_UUID \
"6e400002-b5a3-f393-e0a9-e50e24dcca9e"


BLECharacteristic* telemetryCharacteristic;
BLECharacteristic* commandCharacteristic;


// ============================================================
//                   SAFETY FUNCTIONS
// ============================================================

void stopAllPumps()
{
    digitalWrite(PUMP_LEFT_PIN, LOW);
    digitalWrite(PUMP_CENTER_PIN, LOW);
    digitalWrite(PUMP_RIGHT_PIN, LOW);

    digitalWrite(VALVE_LEFT_PIN, LOW);
    digitalWrite(VALVE_CENTER_PIN, LOW);
    digitalWrite(VALVE_RIGHT_PIN, LOW);

    activeBladder = NONE;
}


// ============================================================
//                  PRESSURE READING
// ============================================================

float readPressure(int pin)
{
    int raw = analogRead(pin);

    /*
     * IMPORTANT:
     * This conversion depends on the exact pressure sensor
     * module and its output circuit.
     *
     * Do NOT treat this as the final calibrated conversion.
     */

    float voltage = (raw / 4095.0) * 3.3;

    // Placeholder conversion for 0-40 kPa sensor.
    float pressure = (voltage / 3.3) * 40.0;

    return pressure;
}


// ============================================================
//                 READ ALL BLADDER PRESSURES
// ============================================================

void readBladderPressures()
{
    leftPressure =
        readPressure(PRESSURE_LEFT_PIN);

    centerPressure =
        readPressure(PRESSURE_CENTER_PIN);

    rightPressure =
        readPressure(PRESSURE_RIGHT_PIN);
}


// ============================================================
//                    PRESSURE SAFETY
// ============================================================

bool safetyCheck()
{
    if (leftPressure >= SAFETY_PRESSURE)
        return false;

    if (centerPressure >= SAFETY_PRESSURE)
        return false;

    if (rightPressure >= SAFETY_PRESSURE)
        return false;

    return true;
}


// ============================================================
//                  CLOSED LOOP CONTROL
// ============================================================

void controlBladder(Bladder bladder)
{
    readBladderPressures();

    // -----------------------------------------
    // GLOBAL SAFETY
    // -----------------------------------------

    if (!safetyCheck())
    {
        stopAllPumps();
        return;
    }


    // -----------------------------------------
    // LEFT
    // -----------------------------------------

    if (bladder == LEFT)
    {
        if (leftPressure < TARGET_PRESSURE)
        {
            digitalWrite(VALVE_LEFT_PIN, HIGH);
            digitalWrite(PUMP_LEFT_PIN, HIGH);

            activeBladder = LEFT;
        }
        else
        {
            digitalWrite(PUMP_LEFT_PIN, LOW);
            digitalWrite(VALVE_LEFT_PIN, LOW);

            activeBladder = NONE;
        }
    }


    // -----------------------------------------
    // CENTER
    // -----------------------------------------

    else if (bladder == CENTER)
    {
        if (centerPressure < TARGET_PRESSURE)
        {
            digitalWrite(VALVE_CENTER_PIN, HIGH);
            digitalWrite(PUMP_CENTER_PIN, HIGH);

            activeBladder = CENTER;
        }
        else
        {
            digitalWrite(PUMP_CENTER_PIN, LOW);
            digitalWrite(VALVE_CENTER_PIN, LOW);

            activeBladder = NONE;
        }
    }


    // -----------------------------------------
    // RIGHT
    // -----------------------------------------

    else if (bladder == RIGHT)
    {
        if (rightPressure < TARGET_PRESSURE)
        {
            digitalWrite(VALVE_RIGHT_PIN, HIGH);
            digitalWrite(PUMP_RIGHT_PIN, HIGH);

            activeBladder = RIGHT;
        }
        else
        {
            digitalWrite(PUMP_RIGHT_PIN, LOW);
            digitalWrite(VALVE_RIGHT_PIN, LOW);

            activeBladder = NONE;
        }
    }


    // -----------------------------------------
    // STOP
    // -----------------------------------------

    else
    {
        stopAllPumps();
    }
}


// ============================================================
//                     MPU6050
// ============================================================

void readMPU()
{
    sensors_event_t accel;
    sensors_event_t gyro;
    sensors_event_t temp;

    mpu.getEvent(
        &accel,
        &gyro,
        &temp
    );

    accelX = accel.acceleration.x;
    accelY = accel.acceleration.y;
    accelZ = accel.acceleration.z;

    gyroX = gyro.gyro.x;
    gyroY = gyro.gyro.y;
    gyroZ = gyro.gyro.z;
}


// ============================================================
//                     BMP180
// ============================================================

void readBMP180()
{
    temperature =
        bmp.readTemperature();

    atmosphericPressure =
        bmp.readPressure() / 100.0;
}


// ============================================================
//                    APDS9960
// ============================================================

void readAPDS()
{
    if (apds.proximityAvailable())
    {
        proximity =
            apds.readProximity();
    }
}


// ============================================================
//                  OLED LOCAL MONITOR
// ============================================================

void updateOLED()
{
    display.clearDisplay();

    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);

    display.setCursor(0, 0);

    display.print("PilloGuard");

    display.setCursor(0, 10);
    display.print("L:");
    display.print(leftPressure, 1);
    display.print(" kPa");

    display.setCursor(0, 20);
    display.print("C:");
    display.print(centerPressure, 1);
    display.print(" kPa");

    display.setCursor(0, 30);
    display.print("R:");
    display.print(rightPressure, 1);
    display.print(" kPa");

    display.setCursor(0, 40);
    display.print("Temp:");
    display.print(temperature, 1);
    display.print(" C");

    display.setCursor(0, 50);
    display.print("BLE:");

    if (bleConnected)
        display.print("CONNECTED");
    else
        display.print("WAITING");

    display.display();
}


// ============================================================
//                    BLE TELEMETRY
// ============================================================

void sendTelemetry()
{
    String packet = "{";

    packet += "\"left_pressure\":";
    packet += String(leftPressure, 2);

    packet += ",\"center_pressure\":";
    packet += String(centerPressure, 2);

    packet += ",\"right_pressure\":";
    packet += String(rightPressure, 2);

    packet += ",\"temperature\":";
    packet += String(temperature, 2);

    packet += ",\"atmospheric_pressure\":";
    packet += String(atmosphericPressure, 2);

    packet += ",\"accel_x\":";
    packet += String(accelX, 2);

    packet += ",\"accel_y\":";
    packet += String(accelY, 2);

    packet += ",\"accel_z\":";
    packet += String(accelZ, 2);

    packet += ",\"gyro_x\":";
    packet += String(gyroX, 2);

    packet += ",\"gyro_y\":";
    packet += String(gyroY, 2);

    packet += ",\"gyro_z\":";
    packet += String(gyroZ, 2);

    packet += ",\"proximity\":";
    packet += String(proximity);

    packet += ",\"active_zone\":\"";

    if (activeBladder == LEFT)
        packet += "LEFT";

    else if (activeBladder == CENTER)
        packet += "CENTER";

    else if (activeBladder == RIGHT)
        packet += "RIGHT";

    else
        packet += "NONE";

    packet += "\"";

    packet += "}";


    telemetryCharacteristic->setValue(
        packet.c_str()
    );

    telemetryCharacteristic->notify();
}


// ============================================================
//                    BLE COMMANDS
// ============================================================

class CommandCallbacks :
    public BLECharacteristicCallbacks
{
    void onWrite(
        BLECharacteristic* characteristic
    )
    {
        std::string value =
            characteristic->getValue();

        if (value.length() == 0)
            return;


        String command =
            String(value.c_str());

        command.trim();
        command.toUpperCase();


        // -----------------------------------------
        // STOP
        // -----------------------------------------

        if (command == "STOP")
        {
            stopAllPumps();
        }


        // -----------------------------------------
        // LEFT
        // -----------------------------------------

        else if (command == "LEFT")
        {
            controlBladder(LEFT);
        }


        // -----------------------------------------
        // CENTER
        // -----------------------------------------

        else if (command == "CENTER")
        {
            controlBladder(CENTER);
        }


        // -----------------------------------------
        // RIGHT
        // -----------------------------------------

        else if (command == "RIGHT")
        {
            controlBladder(RIGHT);
        }
    }
};


// ============================================================
//                      BLE SERVER
// ============================================================

class ServerCallbacks :
    public BLEServerCallbacks
{
    void onConnect(BLEServer* server)
    {
        bleConnected = true;
    }

    void onDisconnect(BLEServer* server)
    {
        bleConnected = false;

        // SAFETY:
        // If the App disconnects, stop pneumatic action.

        stopAllPumps();

        BLEDevice::startAdvertising();
    }
};


// ============================================================
//                       BLE SETUP
// ============================================================

void setupBLE()
{
    BLEDevice::init("PilloGuard");

    BLEServer* server =
        BLEDevice::createServer();

    server->setCallbacks(
        new ServerCallbacks()
    );

    BLEService* service =
        server->createService(
            SERVICE_UUID
        );


    telemetryCharacteristic =
        service->createCharacteristic(
            TELEMETRY_UUID,
            BLECharacteristic::PROPERTY_NOTIFY
        );

    telemetryCharacteristic->addDescriptor(
        new BLE2902()
    );


    commandCharacteristic =
        service->createCharacteristic(
            COMMAND_UUID,
            BLECharacteristic::PROPERTY_WRITE
        );

    commandCharacteristic->setCallbacks(
        new CommandCallbacks()
    );


    service->start();

    BLEAdvertising* advertising =
        BLEDevice::getAdvertising();

    advertising->addServiceUUID(
        SERVICE_UUID
    );

    advertising->setScanResponse(true);

    BLEDevice::startAdvertising();
}


// ============================================================
//                         SETUP
// ============================================================

void setup()
{
    Serial.begin(115200);


    // -----------------------------------------
    // GPIO
    // -----------------------------------------

    pinMode(PUMP_LEFT_PIN, OUTPUT);
    pinMode(PUMP_CENTER_PIN, OUTPUT);
    pinMode(PUMP_RIGHT_PIN, OUTPUT);

    pinMode(VALVE_LEFT_PIN, OUTPUT);
    pinMode(VALVE_CENTER_PIN, OUTPUT);
    pinMode(VALVE_RIGHT_PIN, OUTPUT);


    stopAllPumps();


    // -----------------------------------------
    // I2C
    // -----------------------------------------

    Wire.begin(
        I2C_SDA,
        I2C_SCL
    );


    // -----------------------------------------
    // OLED
    // -----------------------------------------

    if (!display.begin(
        SSD1306_SWITCHCAPVCC,
        0x3C
    ))
    {
        Serial.println(
            "OLED ERROR"
        );
    }


    // -----------------------------------------
    // MPU6050
    // -----------------------------------------

    if (!mpu.begin())
    {
        Serial.println(
            "MPU6050 ERROR"
        );
    }


    // -----------------------------------------
    // BMP180
    // -----------------------------------------

    if (!bmp.begin())
    {
        Serial.println(
            "BMP180 ERROR"
        );
    }


    // -----------------------------------------
    // APDS9960
    // -----------------------------------------

    if (!apds.begin())
    {
        Serial.println(
            "APDS9960 ERROR"
        );
    }
    else
    {
        apds.enableProximity(true);
        apds.enableGesture(true);
    }


    // -----------------------------------------
    // BLE
    // -----------------------------------------

    setupBLE();


    Serial.println(
        "PilloGuard ESP32 READY"
    );
}


// ============================================================
//                          LOOP
// ============================================================

unsigned long lastSensorRead = 0;
unsigned long lastTelemetry = 0;
unsigned long lastOLED = 0;


void loop()
{
    unsigned long now =
        millis();


    // -----------------------------------------
    // SENSOR UPDATE
    // -----------------------------------------

    if (now - lastSensorRead >= 100)
    {
        lastSensorRead = now;

        readBladderPressures();
        readMPU();
        readBMP180();
        readAPDS();


        // -------------------------------------
        // LOCAL SAFETY
        // -------------------------------------

        if (!safetyCheck())
        {
            stopAllPumps();

            Serial.println(
                "!!! PRESSURE SAFETY STOP !!!"
            );
        }
    }


    // -----------------------------------------
    // BLE TELEMETRY
    // -----------------------------------------

    if (now - lastTelemetry >= 500)
    {
        lastTelemetry = now;

        if (bleConnected)
        {
            sendTelemetry();
        }
    }


    // -----------------------------------------
    // OLED
    // -----------------------------------------

    if (now - lastOLED >= 500)
    {
        lastOLED = now;

        updateOLED();
    }


    // -----------------------------------------
    // CLOSED-LOOP CONTROL
    //
    // Once the App sends LEFT/CENTER/RIGHT,
    // pressure feedback keeps running locally.
    // -----------------------------------------

    if (activeBladder != NONE)
    {
        controlBladder(activeBladder);
    }


    delay(5);
}
