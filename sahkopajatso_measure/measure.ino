#define BUFFER_SIZE 5
int roller=0;
int buffer[BUFFER_SIZE]={100,100,100,100,100};
int averageIndex=0;
int cumulativeValue=500;


#define LED 2

void setup()
{
	Serial.begin(9600);
    pinMode(LED,OUTPUT);
}

void loop()
{
    cumulativeValue-=buffer[roller];
	buffer[roller]=analogRead(A0);
    cumulativeValue+=buffer[roller];
    roller=(roller+1)%5;
    if (cumulativeValue<250)
    {
        Serial.println("detected");
        digitalWrite(LED,HIGH);
        delay(1000);
        Serial.println("continue");
        digitalWrite(LED,LOW);
    }  
}
