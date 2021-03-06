import 'dart:convert';
import 'dart:math';
import 'package:toast/toast.dart';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of the application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE test',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: MyHomePage(title: 'Sähköpajatso'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of the application.

  final String title;
  final FlutterBlue flutterBlue = FlutterBlue.instance; //for using Bluetooth LE
  final List<BluetoothDevice> devicesList =
      new List<BluetoothDevice>(); //list of available BLE devices

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //add new devices to the list
  _addBLEDevice(final BluetoothDevice device) {
    if (!widget.devicesList.contains(device)) {
      setState(() {
        widget.devicesList.add(device);
      });
    }
  }

  //we will connect to one of them
  BluetoothDevice _connectedDevice;
  List<BluetoothService> _services;

  //state values for scorekeeping
  int _score = 0;
  int _shotsFired = 0;
  List<int> _previousData = [0, 0, 0, 0];
  List<int> _weights = [1, 1, 1, 1];
  static int availableWeights = 9;

  //takes a bluetooth result, decodes it and updates the score
  void fetchResults(List<int> value) {
    //decode the value
    String newString = utf8.decode(value);

    //check that there is a updated score
    if (newString.startsWith('[')) {
      //parse the string into a list of integers
      List<int> newData = newString
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((e) => int.tryParse(e))
          .toList();
      setState(() {
        //if new hits have been made, increase the score according to the weigths
        for (var i = 0; i < newData.length; i++) {
          _score += (newData[i] - _previousData[i]) * _weights[i] * 1000;
        }
        _previousData = newData;
      });
    } else {
      print(newString);
    }
  }

  //function that selects a device and stops scanning
  _setDevice(BluetoothDevice device) async {
    widget.flutterBlue.stopScan();
    try {
      await device.connect();
    } catch (e) {
      if (e.code != 'already_connected') {
        throw e;
      }
    } finally {
      //get the services of the connected device
      _services = await device.discoverServices();
      await _services.last.characteristics.first
          .setNotifyValue(true); //Subscribe to the score service
      _services.last.characteristics.first.value.listen(fetchResults);
    }
    setState(() {
      _connectedDevice = device;
    });
  }

  //scan for devices
  @override
  void initState() {
    super.initState();

    //add the devices that are already connected
    widget.flutterBlue.connectedDevices
        .asStream()
        .listen((List<BluetoothDevice> devices) {
      for (BluetoothDevice device in devices) {
        _addBLEDevice(device);
      }
    });

    //scan for new devices
    widget.flutterBlue.scanResults.listen((List<ScanResult> results) {
      for (ScanResult result in results) {
        _addBLEDevice(result.device);
      }
    });
    widget.flutterBlue.startScan();
  }

  //builds a list view of available devices
  ListView _buildDevicesList() {
    List<Container> rows = widget.devicesList
        .map((device) => Container(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(device.name == "" ? "???" : device.name),
                        Text(device.id.toString())
                      ],
                    ),
                  ),
                  FlatButton(
                    onPressed: () => _setDevice(device),
                    child: Text(
                      'connect',
                      style: Theme.of(context).accentTextTheme.button,
                    ),
                    color: Theme.of(context).accentColor,
                  ),
                ],
              ),
              height: 50,
            ))
        .toList();
    return ListView(
      padding: EdgeInsets.all(8),
      children: <Widget>[...rows],
    );
  }

  //with these functions the user can adjust the weights for scoring
  void increaseWeight(int i) {
    int remainingWeight = availableWeights;
    for (var weight in _weights) {
      remainingWeight -= weight;
    }
    if (remainingWeight > 0) {
      setState(() {
        _weights[i]++;
      });
    } else {
      Toast.show("All weights in use", context);
    }
  }

  void decreaseWeight(int i) {
    if (_weights[i] > 0) {
      setState(() {
        _weights[i]--;
      });
    } else {
      Toast.show("Weights must be non-negative", context);
    }
  }

  Widget _buildWeightsRow() {
    List<Widget> weightWidgets = _weights.asMap().entries.map((entry) {
      int e = entry.value;
      int i = entry.key;
      return Expanded(
        flex: 1,
        child: Center(
          child: Column(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_drop_up),
                onPressed: () => increaseWeight(i),
              ),
              Center(
                child: Text(
                  '$e',
                  style: Theme.of(context).textTheme.headline3,
                ),
              ),
              IconButton(
                icon: Icon(Icons.arrow_drop_down),
                onPressed: () => decreaseWeight(i),
              ),
            ],
          ),
        ),
      );
    }).toList();

    int remainingWeight = availableWeights;
    for (var weight in _weights) {
      remainingWeight -= weight;
    }

    Widget remaining = Center(
      child: Column(
        children: [
          Text(
            'Remaining',
            style: Theme.of(context).textTheme.headline5,
          ),
          Container(
            height: 12,
          ),
          Text(
            '$remainingWeight',
            style: Theme.of(context).textTheme.headline4,
          ),
        ],
      ),
    );

    return Container(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Container(),
          ),
          Expanded(
            flex: 1,
            child: Container(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: weightWidgets,
              ),
            ),
          ),
          Expanded(flex: 1, child: remaining),
        ],
      ),
    );
  }

  //a view that shows info on a connected device
  Column _buildDeviceView() {
    List<Container> rows = _services
        .map((service) => Container(
              height: 50,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(service.uuid.toString()),
                      ],
                    ),
                  )
                ],
              ),
            ))
        .toList();

    //builds a view that lets user interact with the connected device and shows the available bluetooth services
    return Column(
      children: [
        Container(
          height: 50,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Center(
                  child: Text(_connectedDevice.name ==
                          "" //adds a placeholder for empty names
                      ? "???"
                      : _connectedDevice.name),
                ),
              ),
            ],
          ),
        ),
        Text(
          'Score',
          style: Theme.of(context).textTheme.headline2,
        ),
        Text(
          '$_score',
          style: Theme.of(context).textTheme.headline1,
        ),
        Row(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Shots fired',
                      style: Theme.of(context).textTheme.headline4,
                    ),
                    Text(
                      '$_shotsFired',
                      style: Theme.of(context).textTheme.headline3,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Center(
                child: Column(
                  children: [
                    Text(
                      'Score/Shot',
                      style: Theme.of(context).textTheme.headline4,
                    ),
                    Text(
                      '${(_score / max(_shotsFired, 1)).floor()}',
                      style: Theme.of(context).textTheme.headline3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        FlatButton(
          onPressed: () {
            setState(() {
              _score = 0;
              _shotsFired = 0;
            });
          }, //resets the score
          child: Text(
            "Restart",
            style: Theme.of(context).accentTextTheme.button,
          ),
          color: Theme.of(context).accentColor,
        ),
        Text(
          'Weights',
          style: Theme.of(context).textTheme.headline4,
        ),
        _buildWeightsRow(),
        RaisedButton(
          onPressed: () async {
            setState(() {
              _shotsFired++;
            });
            await _services.last.characteristics.first.write(utf8.encode('s'));
          }, //sends the string 's' (shoot) to the BLE-module when the button is pressed
          child: Text(
            "Shoot",
            style: TextStyle(
                fontSize: 32.0, textBaseline: TextBaseline.alphabetic),
          ),
          color: Theme.of(context).accentColor,
          textColor: Theme.of(context).accentTextTheme.button.color,
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 32),
        ),
      ],
    );
  }

  //show a device view if one is connected
  Widget _buildBody() {
    if (_connectedDevice != null) {
      return _buildDeviceView();
    }
    return _buildDevicesList();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }
}
