2019 IC Design Contest Preliminary
<font color="#f00">大學部</font> 標準元件數位電路設計
<font color="#0f0">Image Convolutional Circuit Design</font>
===

## 目的
在搜尋資料後，發現IC Contect的考古題在github上看到其他人的實作。往往缺少詳細說明。因此，此文章的目的是為了讓讀者了解後，就有辦法自行實作，而非trace code。同時也記錄我實作時的想法。

## 實作流程
詳細題目說明參見官方公布之文件，建議閱讀順序為:
問題說明(注意資料尺寸) > I/O input > 畫系統方塊圖(注意控制訊號之I/O)</br>
其餘時序細節，在建構完FSM後，再一一實作即可，不需急於了解。

### 1. FSM
看完說明後，藉由資料尺寸之條件、運行流程，即可建立出FSM，以**最少的state**為目標繪製。繪製時可能會對一些條件的準確度，如4095/4096之counter選擇有所顧慮，這可以先忽略。待確定FSM能順利停下，完成一次的跑動，再決定即可，實作FSM如下:
![](https://i.imgur.com/bgJ8hpA.png)

|state|說明|
|-----|---|
|IDLE|reset後進入, 等待啟動訊號|
|INPUT_F|重複9個clk，從cnn_sti.dat讀入3*3大小的feature input data，並做一個乘法運算|
|WRITE_L0|將計算為的資料存到MEM_L0中|
|READ_L0|重複4個clk，從MEM_L0讀取CONV的結果, 同時進行比大小的運算|
|WRITE_L1|將最大值寫入MEM_L1中|

PS: 許多大神的FSM有一個finish state確定整個執行停止，但我的想法是停在IDLE當作機器閒置，可不用reset，就直接給予下一個input data。

### 2. enable signal
確認FSM正確無誤後，就可以運用state來準確地給予控制訊號。有crd、cwr、csel三個控制記憶體訊號。分別用3個always block寫較好控制。**特別注意** crd、cwr為edge trigger。

|signal|說明|
|-|-|
|crd|1. edge trigger<br/> 2. READ_L0 state觸發|
|cwr|1. edge trigger<br/> 2. WRITEE_L0、WRITEE_L1 state觸發|
|csel|3'b000: 沒有選擇記憶體<br/> 3'b001: 選擇MEM_L0，READ_L0、WRITE_L0觸發<br/>3'b011: 選擇MEM_L1，WRITE_L1觸發|

### 3. fetch input data </font></br>
這部分testfixture.v已經寫好了，只需要指定iaddr的輸出訊號，就可從idata取得對應index的資料。而iaddr的範圍為0~4095，官方公布的文檔有誤。

### 4. CONV
CONV層包含zero-padding、convolution、ReLU三種計算。各別實作方式如下:
![](https://i.imgur.com/2GP99ia.png)
從上圖可以看到，我們convolution取值和存值的位置。如果取值是以kernal map的中心為移動座標，存值的座標則是相同。因此建議在shift kernal時，以kernal map中心為座標。
- Zero-padding
>當kernal map shift到邊界時，會有資料超出input feature範圍(藉由kernal map的中心座標判斷)。直接assign取出的值為0，就可達到zero padding的效果。
- Convolution
>這部分攸關乘法計算，一次的convolution是分成9個clk取值、計算，因此理論上只需要一個乘法器即可。但因為weight的不同，可能有些寫法會合出9個乘法器，差異如下:
![](https://i.imgur.com/S2t7xM4.png)
右邊的是9個clk，依序餵不同的weight到multiplier中，這種方法只需要一個multiplier。但左邊的是input feature data直接餵給9個weight，之後再決定要取哪個data，因此會需要9個乘法器。相比之下，是**右邊的比較好***。
**PS: 這年的競賽對面積也所要求，兩者的面積會差8個20 bit乘法器**
- ReLU
>這只需要在存值之前，判斷MSB是0或1，在決定儲存數值即可。

### 5. Maxpooling
大概有兩種做法，常見的是讀四個後再一次比大小。另一種是讀一次比一次大小。我是使用讀一次就比一次大小，這個方法可以減少register的使用。

## 特別注意
### 關於index的特別寫法:
我們的feature map為64 * 64，共4096個pixel，因此index需要12個bit。一般而言，我們在shift kernal map的概念是column、row，也就是在assign index的時候會運用到乘法的運算如下:
>index = row * 64 + column (ex. 4095 = 63 * 64 + 63)

再參考了各路大神的寫法後，發現乘法的運算是可以避免的，只要利用bitwise的概念即可，如下圖:
![](https://i.imgur.com/tBzNtFG.png)
將index 12-bit拆成高位6-bit、低位6-bit。如上方例子，如果高位6-bit加一，則表示index加64，也就是index向下位移一個row，相當於上方`index row*64`的計算，這個高位元組加1的動作，就取代乘法運算。

### 定點浮點數運算:
這部分我並不太確定，但就實作結果而言我是正確的。此浮點數定義為4-bit整數、16-bit小數，若兩個這樣的浮點數相乘，則變成8-bit整數、32-bit小數，如下圖:</bt>
![](https://i.imgur.com/BGGuaNR.png) </br>
由於定點數的關係，取值時，直接擷取
