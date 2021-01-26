import 'package:flutter/material.dart';

import 'package:flutter/cupertino.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qrscan/qrscan.dart' as scanner;

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:http/http.dart' as http;

import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'dart:io';

//여기서 부터 firebase알람용
final Map<String, Item> _items = <String, Item>{};

Item _itemForMessage(Map<String, dynamic> message) {
  final dynamic data = message['notification'] ?? message;

  final String itemId = data['title'];
  final Item item = _items.putIfAbsent(itemId, () => Item(itemId: itemId))
    ..status = data['body'];

  return item;
}

class Item {
  Item({this.itemId});

  final String itemId;

  StreamController<Item> _controller = StreamController<Item>.broadcast();

  Stream<Item> get onChanged => _controller.stream;

  String _status;

  String get status => _status;

  set status(String value) {
    _status = value;
    _controller.add(this);
  }

  static final Map<String, Route<void>> routes = <String, Route<void>>{};

  Route<void> get route {
    final String routeName = '/detail/$itemId';
    return routes.putIfAbsent(
      routeName,
      () => MaterialPageRoute<void>(
        settings: RouteSettings(name: routeName),
        builder: (BuildContext context) => DetailPage(itemId),
      ),
    );
  }
}

class DetailPage extends StatefulWidget {
  DetailPage(this.itemId);

  final String itemId;

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Item _item;
  StreamSubscription<Item> _subscription;

  @override
  void initState() {
    super.initState();
    _item = _items[widget.itemId];
    _subscription = _item.onChanged.listen((Item item) {
      if (!mounted) {
        _subscription.cancel();
      } else {
        setState(() {
          _item = item;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Item ${_item.itemId}"),
      ),
      body: Material(
        child: Center(child: Text("Item status: ${_item.status}")),
      ),
    );
  }
}
//firebase 알람용 아래는 화면 만드는용

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: '테스트용'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BleManager _bleManager = BleManager();
  String _homeScreenText = "wait";
  int _counter = 0;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();
  final TextEditingController _topicController =
      TextEditingController(text: 'topic');
  String qrcode = "";
  DateTime date = DateTime.now();
  String time = "";
  var httpResult = "";
  TextEditingController _inputController = new TextEditingController();
  TextEditingController _outputController = new TextEditingController();
  String message2 = "";

//앱켜져있을때 알람받으면 dialog로 보여주는용
  Widget _buildDialog(BuildContext context, Item item) {
    return AlertDialog(
      content: Text("Item ${item.itemId} has been updated"),
      actions: <Widget>[
        FlatButton(
          child: const Text('CLOSE'),
          onPressed: () {
            Navigator.pop(context, false);
          },
        ),
        FlatButton(
          child: const Text('SHOW'),
          onPressed: () {
            Navigator.pop(context, true);
          },
        ),
      ],
    );
  }

  void _showItemDialog(Map<String, dynamic> message) {
    showDialog<bool>(
      context: context,
      builder: (_) => _buildDialog(context, _itemForMessage(message)),
    ).then((bool shouldNavigate) {
      if (shouldNavigate == true) {
        //보기 누를시
        //_navigateToItemDetail(message);//다른화면을 열며 내용을 보여준다
        final dynamic data = message['notification'] ?? message;

        setState(() {
          message2 = "제목: " + data['title'] + "\n내용: " + data['body'];
        });
      }
    });
  }

  void _navigateToItemDetail(Map<String, dynamic> message) {
    // 내용 보여줄 화면 만들기로 추정됨
    final Item item = _itemForMessage(message);
    // Clear away dialogs
    Navigator.popUntil(context, (Route<dynamic> route) => route is PageRoute);
    if (!item.route.isCurrent) {
      Navigator.push(context, item.route);
    }
  }

  @override
  void initState() {
    //앱 켜져 있을시 직접 메세지 받기
    super.initState();
    _firebaseMessaging.configure(
      onMessage: (Map<String, dynamic> message) async {
        print("onMessage: $message");
        _showItemDialog(message);
      },
      onLaunch: (Map<String, dynamic> message) async {
        print("onLaunch: $message");
        _navigateToItemDetail(message);
      },
      onResume: (Map<String, dynamic> message) async {
        print("onResume: $message");
        _navigateToItemDetail(message);
      },
    );
    _firebaseMessaging.requestNotificationPermissions(
        const IosNotificationSettings(
            sound: true, badge: true, alert: true, provisional: true));
    _firebaseMessaging.onIosSettingsRegistered
        .listen((IosNotificationSettings settings) {
      print("Settings registered: $settings");
    });
    _firebaseMessaging.getToken().then((String token) {
      assert(token != null);
      setState(() {
        _homeScreenText = "Push Messaging token: $token";
      });
      print(_homeScreenText);
    });
  }

//여기까지가 firebase 메세지 받으면 사용하는  함수들

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              child: Row(
                children: [
                  FlatButton(
                    child: Text('QRcode', style: TextStyle(fontSize: 24)),
                    onPressed: _qrScan,
                    color: Colors.green,
                    textColor: Colors.white,
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Container(
                          child: Text('$qrcode'),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Text("\n"),
            Container(
              child: Row(
                children: [
                  FlatButton(
                    child: Text('알람', style: TextStyle(fontSize: 24)),
                    onPressed: _qrScan,
                    color: Colors.green,
                    textColor: Colors.white,
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Container(
                          child: Text('$message2'),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Text("\n"),
            Container(
              child: Row(
                children: [
                  FlatButton(
                    child: Text('날짜', style: TextStyle(fontSize: 24)),
                    onPressed: _datePicker,
                    color: Colors.green,
                    textColor: Colors.white,
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Container(
                          child: Text("${date.toLocal()}".split(' ')[0]),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Text("\n"),
            Container(
              child: Row(
                children: [
                  FlatButton(
                    child: Text('시간', style: TextStyle(fontSize: 24)),
                    onPressed: _timePicker,
                    color: Colors.green,
                    textColor: Colors.white,
                  ),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Container(
                          child: Text('$time'),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Text("\n"),
            Container(
              child: Row(
                children: [
                  FlatButton(
                    child: Text('http통신', style: TextStyle(fontSize: 24)),
                    onPressed: _httpConnection,
                    color: Colors.green,
                    textColor: Colors.white,
                  ),
                  Expanded(
                      child: Column(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        // 컨테이너 내부 하단에 8픽셀만큼 패딩 삽입
                        child: Text(
                          // 컨테이너의 자식으로 텍스트 삽입
                          "$httpResult",
                          style:
                              TextStyle(fontWeight: FontWeight.bold // 텍스트 강조 설정
                                  ),
                        ),
                      ),
                    ],
                  )),
                ],
              ),
            ), //----------------------------

            Text("\n"),
            Container(
              child: Row(
                children: [
                  FlatButton(
                    child: Text('블루투스', style: TextStyle(fontSize: 24)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => bluetoothWidget()),
                      );
                    },
                    color: Colors.green,
                    textColor: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  Future _qrScan() async {
    await Permission.camera.request();
    String barcode = await scanner.scan();
    setState(() {
      if (barcode == null) {
        print('nothing return.');
      } else {
        qrcode = barcode;
      }
    });
  }

  Future _datePicker() async {
    final DateTime picked = await showDatePicker(
      context: context,
      initialDate: date, // Refer step 1
      firstDate: DateTime(2000),
      lastDate: DateTime(2025),
    );
    if (picked != null && picked != date)
      setState(() {
        date = picked;
      });
  }

  Future _timePicker() async {
    TimeOfDay selectedTime = TimeOfDay(hour: 00, minute: 00);
    String _hour, _minute, _time;
    final TimeOfDay picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (picked != null)
      setState(() {
        selectedTime = picked;
        _hour = selectedTime.hour.toString();
        _minute = selectedTime.minute.toString();
        _time = _hour + ' : ' + _minute;
      });
    if (picked != null && picked != time)
      setState(() {
        time = _time;
      });
  }

  Future _httpConnection() async {
    String url =
        "https://maeulro.sharenshare.kr/user/alert/select/C214ACE3986F4";
    var response = await http.get(url);

    setState(() {
      // httpResult = response.statusCode;
      // httpResult = response.headers;
      httpResult = response.body;
    });
  }
}

@override
State<StatefulWidget> createState() {
  // TODO: implement createState
  throw UnimplementedError();
}

//블루투스 화면 위잿화
class bluetoothWidget extends StatefulWidget {
  @override
  _bluetoothHompage createState() => _bluetoothHompage();
}

//블루투스 페이지
class _bluetoothHompage extends State<bluetoothWidget> {
  BleManager _bleManager = BleManager(); //BLE 메니저
  bool _isScanning = false; //스캔 확인용
  List<BleDeviceItem> deviceList = []; //BLE 정보 저장용

  @override
  void initState() {
    init(); //BLE 초기화
  }

  void init() async {
    //BLE 생성
    await _bleManager
        .createClient(
            restoreStateIdentifier: "example-restore-state-identifier",
            restoreStateAction: (peripherals) {
              peripherals?.forEach((peripheral) {
                print("Restored peripheral: ${peripheral.name}");
              });
            })
        .catchError((e) => print("Couldn't create BLE client  $e"))
        .then((_) => _checkPermissions()) //BLE 생성 후 퍼미션 체크
        .catchError((e) => print("Permission check error $e"));
    //.then((_) => _waitForBluetoothPoweredOn())
  }

  //퍼미션 체크 및 없으면 퍼미션 동의 화면 출력
  _checkPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.contacts.request().isGranted) {}
      Map<Permission, PermissionStatus> statuses =
          await [Permission.location].request();
      print(statuses[Permission.location]);
    }
  }

  //스캔 ON/OFF
  void scan() async {
    if (!_isScanning) {
      deviceList.clear();
      _bleManager.startPeripheralScan().listen((scanResult) {
        // 페리페럴 항목에 이름이 있으면 그걸 사용하고
        // 없다면 어드버타이지먼트 데이터의 이름을 사용하고 그것 마져 없다면 Unknown으로 표시
        var name = scanResult.peripheral.name ??
            scanResult.advertisementData.localName ??
            "Unknown";
        /*
        // 여러가지 정보 확인
        print("Scanned Name ${name}, RSSI ${scanResult.rssi}");
        print("\tidentifier(mac) ${scanResult.peripheral.identifier}"); //mac address
        print("\tservice UUID : ${scanResult.advertisementData.serviceUuids}");
        print("\tmanufacture Data : ${scanResult.advertisementData.manufacturerData}");
        print("\tTx Power Level : ${scanResult.advertisementData.txPowerLevel}");
        print("\t${scanResult.peripheral}");
        */
        //이미 검색된 장치인지 확인 mac 주소로 확인
        var findDevice = deviceList.any((element) {
          if (element.peripheral.identifier ==
              scanResult.peripheral.identifier) {
            //이미 존재하면 기존 값을 갱신.
            element.peripheral = scanResult.peripheral;
            element.advertisementData = scanResult.advertisementData;
            element.rssi = scanResult.rssi;
            return true;
          }
          return false;
        });
        //처음 발견된 장치라면 devicelist에 추가
        if (!findDevice) {
          deviceList.add(BleDeviceItem(name, scanResult.rssi,
              scanResult.peripheral, scanResult.advertisementData));
        }
        //갱긴 적용.
        setState(() {});
      });
      //스캔중으로 변수 변경
      setState(() {
        _isScanning = true;
      });
    } else {
      //스캔중이었다면 스캔 정지
      _bleManager.stopPeripheralScan();
      setState(() {
        _isScanning = false;
      });
    }
  }

  //디바이스 리스트 화면에 출력
  list() {
    return ListView.builder(
      itemCount: deviceList.length,
      itemBuilder: (context, index) {
        return ListTile(
          //디바이스 이름과 맥주소 그리고 신호 세기를 표시한다.
          title: Text(deviceList[index].deviceName),
          subtitle: Text(deviceList[index].peripheral.identifier),
          trailing: Text("${deviceList[index].rssi}"),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("블루투스"),
      ),
      body: Center(
        //디바이스 리스트 함수 호출
        child: list(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: scan, //버튼이 눌리면 스캔 ON/OFF 동작
        child: Icon(_isScanning
            ? Icons.stop
            : Icons.bluetooth_searching), //_isScanning 변수에 따라 아이콘 표시 변경
      ),
    );
  }
}

//디바이스 정보 저장용 클래스
class BleDeviceItem {
  String deviceName;
  Peripheral peripheral;
  int rssi;
  AdvertisementData advertisementData;

  BleDeviceItem(
      this.deviceName, this.rssi, this.peripheral, this.advertisementData);
}

void main() {
  runApp(MyApp());
}
