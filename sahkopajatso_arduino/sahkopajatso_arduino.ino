#include <stdio.h> //for constructing strings

#define NUM_MEASURES 4                            //number of coin detectors
int measurePins[NUM_MEASURES] = {A3, A2, A1, A0}; //remember to update if you change the number of measures or pin order
int scoreHits[NUM_MEASURES] = {0};                //this is the number of times each detector has detected a coin

#define BUFFER_SIZE 5 //when detecting the coins we use the sum of the last N elements (effectively same as average) to get rid of some noise
int roller = 0;       //tells which value in the sum is to be updated
//Annoyingly, the values depend on lighting conditions, so it is better to calibrate. This also makes using different kinds of photoresistors easier.
int buffer[NUM_MEASURES][BUFFER_SIZE];    //The buffered values that are what we get staright from the detector
int thresholds[NUM_MEASURES];             //These are the thresholds of the cumulative values for detection, and they need to be calibrated. If the cumulative value is below the threshold, a coin is covering the photoresistor
int cumulativeValues[NUM_MEASURES] = {0}; //These are the sums of the values in the buffer. They have to be calibrated.

#define CALIBRATION_ROUNDS 20 //how many measurements are done for calibrating each detector

#define DETECTION_TIME 1000      // We only want to send information about one detection when a coin passes over the detector, so we stop registering them for a second
unsigned long lastDetection = 0; //This tracks the moment when we registered a hit last time. Since this is in milliseconds, it is important to use longs, and still there will be an overflow in 50 days.

unsigned long lastShot = 0; //This tracks the moment when we registered a shot last time.
#define RELOAD_TIME 1000    //time between shooting and reloading

#define SHOOT_PIN 8 //pins for using the relay
#define RELOAD_PIN 9

void calibrate() //for calibrating the coin detectors
{
  //measure a cumulative result for some time
  for (int round = 0; round < CALIBRATION_ROUNDS; round++)
  {
    for (int i_measure = 0; i_measure < NUM_MEASURES; i_measure++)
    {
      cumulativeValues[i_measure] += analogRead(measurePins[i_measure]);
    }
  }

  //calculate the calibrated values for each detector
  for (int i_measure = 0; i_measure < NUM_MEASURES; i_measure++)
  {
    cumulativeValues[i_measure] /= CALIBRATION_ROUNDS;         //get the average measurement
    for (int i_buffer = 0; i_buffer < BUFFER_SIZE; i_buffer++) //fill the buffer with average values
    {
      buffer[i_measure][i_buffer] = cumulativeValues[i_measure];
    }
    cumulativeValues[i_measure] *= BUFFER_SIZE;              //calculate the expected cumulative value
    thresholds[i_measure] = cumulativeValues[i_measure] / 2; //calculate a calibrated detection threshold
  }
}

void sendScore() //A helper function for sending the score over BLE
{
  Serial.print('[');
  for (int i = 0; i < NUM_MEASURES; i++)
  {
    if (i > 0)
    {
      Serial.print(',');
    }
    Serial.print(scoreHits[i]);
  }
  Serial.print("]\n");
}

void measure() //Controls the coin detectors to find out whether they have detected coins
{
  for (int i_measure = 0; i_measure < NUM_MEASURES; i_measure++) //iterate over the coin detectors
  {
    int previousCumulative = cumulativeValues[i_measure];                                                  //previous value of the sum of the buffer for comparison
    cumulativeValues[i_measure] -= buffer[i_measure][roller];                                              //since the cumulative value is only for the 5 most recent values, we remove the oldest one
    buffer[i_measure][roller] = analogRead(measurePins[i_measure]);                                        //measure a new value
    cumulativeValues[i_measure] += buffer[i_measure][roller];                                              //and add it to the cumulative value
    if (cumulativeValues[i_measure] <= thresholds[i_measure] && millis() - lastDetection > DETECTION_TIME) //if the cumulative value has dropped under the threshold, and at least a second has passed since the last one, send a message over the Bluetooth
    {
      scoreHits[i_measure]++; //register the hit
      sendScore();            //send the score over BLE

      lastDetection = millis(); //update the time of the last detection
      digitalWrite(LED_BUILTIN, HIGH);
    }
    else if (millis() - lastDetection > DETECTION_TIME) //if a second has passed since the last valid detection, turn the led off
    {
      if (millis() - lastShot > RELOAD_TIME) //TODO placeholder
      {
        digitalWrite(LED_BUILTIN, LOW);
      }
    }
  }
  roller = (roller + 1) % BUFFER_SIZE; //update the index of the oldest element in the buffer. Thsi loops over buffer size
}

//shoot a coin into the pajatso
void shoot()
{
  if (millis() - lastShot < 4 * RELOAD_TIME)
  {
    digitalWrite(SHOOT_PIN, HIGH);
    digitalWrite(RELOAD_PIN, HIGH);
    delay(1000);
  }

  lastShot = millis();
  digitalWrite(LED_BUILTIN, HIGH); //Indicator
  digitalWrite(SHOOT_PIN, LOW);    //set the relay to shoot
  digitalWrite(RELOAD_PIN, HIGH);
}

//prepare the mechanical parts for the next shot
void reload()
{
  if (millis() - lastShot > RELOAD_TIME)
  {
    if (millis() - lastShot > 3 * RELOAD_TIME || millis() - lastShot < 2 * RELOAD_TIME) //if enough time for reloading  has passed, don't send current to the motor
    {
      digitalWrite(SHOOT_PIN, HIGH);
      digitalWrite(RELOAD_PIN, HIGH);
    }
    else //if enough time for shooting has passed, reload
    {
      digitalWrite(SHOOT_PIN, HIGH);
      digitalWrite(RELOAD_PIN, LOW);
    }

    if (millis() - lastDetection > DETECTION_TIME) //indicator
    {
      digitalWrite(LED_BUILTIN, LOW);
    }
  }
}

//We use a character in the beginning of the command to recognize which command it is
#define SHOOT 's'

char command;
void instructions() //read instructions from serial and react accordingly
{
  if (Serial.available() > 0)
  {
    command = Serial.read();

    if (command == SHOOT)
    {
      /*
      float power=Serial.parseFloat(); //Try to read the power at which the coin is shot
      */
      Serial.println("Shooting"); //print a value for debugging
      shoot();
    }
    else
    {
      Serial.print("Unknown command: ");
      Serial.println(command);
    }
  }
}

void setup()
{
  delay(3000);                  //this might be safer in some way
  Serial.begin(9600);           //default communication rate of the Bluetooth module
  pinMode(LED_BUILTIN, OUTPUT); //for testing with the onboard led
  pinMode(RELOAD_PIN, OUTPUT);
  pinMode(SHOOT_PIN, OUTPUT);
  calibrate(); //calibrate the detectors
}

void loop()
{
  instructions();
  measure();
  reload();
}
