## Bitcoinウォレットを実装する

Bitcoinの仕組みについてより深く解説するため、実際に筆者が簡易的なBitcoinウォレットをRubyで実装した。（[bcwallet.rb](https://github.com/peryaudo/bcwallet)）

Rubyの標準ライブラリのみで書かれ、コメント・空行を除いて800行程度と、非常にコンパクトに収まったと自負している。

全体のソースコードはGithubにアップロードしたのでご覧頂きたい。

<div class="figure"><a href = "https://github.com/peryaudo/bcwallet"><img src="res/fig_bcwallet_github.png" alt="Githubのページへ"><p class="caption">Githubのページへ</p></a></div>

この章では、実際にこのクライアントのソースコードを解説しつつ、Bitcoinの仕組みについてさらに詳しく掘り下げていく。

Rubyに慣れていない読者もおられるかもしれないが、決してRubyとして高度な使い方をしている訳ではないのでどうかお付き合いいただきたい。

以下ではソースコードを引用しながら解説していくが、その全てを掲載する訳ではないので、適宜Githubの完全版を参照してほしい。

ダウンロードデータが小さい方が気軽にテストしやすく、また、ハッシュ木（Merkle Tree）などの概念の解説に適切であるため、このクライアントはSimplified Payment Verificationを採用することとした。

また、本質とあまり関係がないため、実用的なBitcoinクライアントが行わなければいけない検証の一部（とくにブロックが正しいチェーンの一部かどうか等）は省くこととした。

<!--ADS-->

<!--TOC-->

### Testnet（テストネット）

さっそく、bcwallet.rbのコードを読み解いていこう。

    #
    # DO NOT SET THIS VALUE "false".
    #
    IS_TESTNET = true

Bitcoinのクライアントの開発中には、バグやセキュリティホールによってコインなどを喪失してしまう可能性がある。

そこで使われるのが[Testnet](https://en.bitcoin.it/wiki/Testnet)(Bitcoin Wiki, 英語)である。Testnetはコインが実際の価値を持たないよう工夫されたBitcoinのネットワークであり、メインのネットワークからは独立している。Testnetのコインは[TestNet Faucet](https://tpfaucet.appspot.com/)において無料で手に入れることができる。

また、TestnetのBlockchainは[TEST Bitcoin Block Explorer](http://blockexplorer.com/testnet)で閲覧することができる。

上で公開されているBitcoinクライアントを実際に試す際にはTestnetをお使いいただきたい。

<div class="tip"><p>以下、しばらくBitcoinのプロトコルの本質とあまり関係のない話（アドレスの文字列の生成方法やブルームフィルターなど）が続くので、しばらくの間ご辛抱願いたい。（退屈に思われた方は、「Bitcoinプロトコル」の節まで飛ばして頂いて構わない）</p></div>

### 使われる電子署名アルゴリズムとハッシュ関数

Bitcoinの電子証明には、ECDSA（楕円曲線電子署名アルゴリズム）が用いられている。本家の実装（Satoshi Nakamoto自身が実装したことからSatoshi Clientとも言う）ではOpenSSLのライブラリを使って電子署名を行っており、この実装でもOpenSSLを利用する。

Keyクラスは、OpenSSLライブラリを介して、楕円曲線暗号の公開鍵・秘密鍵のペアを管理するクラスである。

    class Key
    public
      def self.hash256(plain)
        return OpenSSL::Digest::SHA256.digest(OpenSSL::Digest::SHA256.digest(plain))
      end
    
      def self.hash160(plain)
        return OpenSSL::Digest::RIPEMD160.digest(OpenSSL::Digest::SHA256.digest(plain))
      end

Bitcoinではハッシュは様々な所で用いられるが、そのほとんど全てで、SHA-256を2回適用した物が使われる。しかし、より短いハッシュが必要な場合（たとえばアドレスなど）は、1回SHA-256を適用した物に、さらにもう1回RIPEMD-160を適用した物が用いられる。（上のコードの通りである）

以降これらを単にHash256, Hash160と呼ぶことにする。

### アドレスや秘密鍵の文字表現

Bitcoinでは、バイナリ列を人が読み書きできる形式に変換する必要がある時は、Base58が用いられる。Base58は、Base64と似ているが、書体によっては紛らわしい複数の文字や、スラッシュが取り除かれているという点でBase64と異なる。


      BASE58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
      def self.encode_base58(plain)
        # plain is big endian
    
        num = plain.unpack("H*").first.hex
    
        res = ''
    
        while num > 0
          res += BASE58[num % 58]
          num /= 58
        end
    
        # restore leading zeroes
        plain.each_byte do |c|
          break if c != 0
          res += BASE58[0]
        end
    
        return res.reverse
      end
    
      def self.decode_base58(encoded)
        num = 0
        encoded.each_char do |c|
          num *= 58
          num += BASE58.index(c)
        end
    
        res = num.to_s(16)
    
        if res % 2 == 1 then
          res = '0' + res
        end
    
        # restore leading zeroes
        encoded.each_char do |c|
          break if c != BASE58[0]
          res += '00'
        end
    
        return [res].pack('H*')
      end

Bitcoinのアドレスや秘密鍵（のエクスポート用のフォーマット）は、主データにチェックサムと種別を添えてBase58でエンコードした物である。これはSatoshi Clientにおける関数名に従って、[Base58Check](https://en.bitcoin.it/wiki/Base58Check_encoding)と呼ばれている。

具体的には、「種別（1バイト）＋主データ＋「種別（1バイト）＋主データ」のHash256の頭4バイト」をBase58エンコードした物　である。

種別のバイトは以下の通りである。（10進数）

|種別 | 公開鍵 | 秘密鍵 |
|------|---|-----|
| Main | 0 | 128 |
| Testnet | 111 | 239 |

      def self.encode_base58check(type, plain)
        leading_bytes = {
          :main    => { :public_key => 0,   :private_key => 128 },
          :testnet => { :public_key => 111, :private_key => 239 }
        }
    
        leading_byte = [leading_bytes[IS_TESTNET ? :testnet : :main][type]].pack('C')
    
        data = leading_byte + plain
        checksum = Key.hash256(data)[0, 4]
    
        return Key.encode_base58(data + checksum)
      end
    
      def self.decode_base58check(encoded)
        decoded = Key.decode_base58(encoded)
    
        raise "invalid base58 checksum" if Key.hash256(decoded[0, decoded.length - 4])[0, 4] != decoded[-4, 4]
    
        types = {
          :main    => { 0   => :public_key, 128 => :private_key },
          :testnet => { 111 => :public_key, 239 => :private_key }
        }
    
        type = types[IS_TESTNET ? :testnet : :main][decoded[0].unpack('C').first]
    
        return {:type => type, :data => decoded[1, decoded.length - 5]}
      end

Bitcoinのアドレスは、Hash160(公開鍵)をBase58Checkでエンコードした物である。

      def to_address_s
        return Key.encode_base58check(:public_key, Key.hash160(@key.public_key.to_bn.to_s(2)))
      end

### ブルームフィルター

    class BloomFilter

BloomFilterクラスは、データからブルームフィルターを構築するクラスである。

Simplified Payment Verification（分からない方は[Bitcoinウォレットの比較](comparison.html)と[Bitcoinの細部](detail.html)で復習！）はBitcoin論文で言及はされているものの、実際には、データを部分的にダウンロードする方法というのは長年存在しなかったので、これまで効率的にSPVクライアントを実装する事はできなかった。

しかし、[BIP 0037](https://github.com/bitcoin/bips/blob/master/bip-0037.mediawiki)で提案されたプロトコル拡張によって、「ブルームフィルター」を用いて、自分のアドレスに関連するトランザクションのみをダウンロードしてくる事ができるようになった。

ブルームフィルターは、非常に高速に動作し、ある要素が集合に含まれるかどうかを、確率的に判定できるデータ構造である。「確率的」というのは、「含まれない物を、含まれると言ってしまうかもしれないが、含まれるものを含まれないと言ってしまうことはない」という特徴（つまり、偽陽性はあるが偽陰性は無い）の事を指している。

ブルームフィルターは極めて単純な仕組みで成り立っている。まず、フィルターは0と1のみで成り立つ（ブール値の）長さNの配列だとする。

あるデータに対して常に同一の、hash_funcs個の、N以下の整数を返すハッシュ関数を考える。このデータを追加する時は、このハッシュ関数の返り値と同じインデックスの配列の要素を、すべて1にすればよい。（既に1の場合そのまま）

あるデータが含まれるかの判定は、逆にそれらの配列の要素がすべて1であれば、「おそらく」ブルームフィルターに含まれていると言える。

問題は、ハッシュ関数を何とするかであるが、Bitcoinでは[MurmurHash3](https://code.google.com/p/smhasher/source/browse/trunk/MurmurHash3.cpp)と呼ばれる非暗号的ハッシュ関数を使っている。

MurmurHashは、シードとデータを引数として取る。

      def hash(seed, data)

Bitcoinでは、シード値を、i <- [0 .. hash_funcs - 1] について、i * 0xfba4c795 + tweakで計算して、帰ってきたMurmurHashの値のmodを取って、そのビットを塗っている。（tweakは適当な乱数で、後述のfilterloadメッセージでフィルターのデータと共に送信する）

      def insert(data)
        @hash_funcs.times do |i|
          set_bit(hash(i * 0xfba4c795 + @tweak, data) % (@filter.length * 8))
        end
      end


### Bitcoinプロトコル

いよいよ、Bitcoinのプロトコルの解説に入る。

Networkクラスは、実際のネットワークとの通信を扱うクラスである。


    class Network
    private
      PROTOCOL_VERSION = 70001

BitcoinはP2Pのプロトコルであるため、本来であれば、複数のノードとデータのやりとりをしなければいけないが、簡素化のため、このクライアントは一つのノードとのみ通信をすることとしている。したがって、本来であればネットワークに関係するクラスは複数必要かもしれないが、ここでは一つのみとしている。

Bitcoinは非同期的に相手クライアントとメッセージをやりとりすることで情報の共有をはかる。

メッセージの受信・送信・シリアライズを行うのは、read\_message(), write\_message(), serialize\_message()である。

      def write_message(message)
        # Create payload
        serialize_message(message)
    
        # 4bytes: magic
        raw_message = [IS_TESTNET ? '0b110907' : 'f9beb4d9'].pack('H*')
    
        # 12bytes: command (padded with zeroes)
        raw_message += [message[:command].to_s].pack('a12')
    
        # 4bytes: length of payload
        raw_message += [@payload.length].pack('V')
    
        # 4bytes: checksum
        raw_message += Key.hash256(@payload)[0, 4]
    
        # payload
        raw_message += @payload
    
        @socket.write raw_message
        @socket.flush
      end

全てのメッセージは、このフォーマットに従って送信される。以降、ネットワークアドレスとOpenSSLから受け取るバイト列以外の、ほとんど全ての数値はリトル・エンディアンであることに注意。


| バイト数 | 内容 | 解説 |
|------|---|-----|
| 4 | マジック | Testnetなら0b 11 09 07、メインではf9 be b4 d9 |
| 12| コマンド | 送信するコマンドのASCII文字列。<br>余ったバイトは0で埋められる。<br>（埋めていないと無視される）|
| 4 | ペイロードの長さ | 送信するデータの本体の長さ |
| 4 | チェックサム | ペイロードのチェックサム、<br>Hash256した物の頭4バイト |
| ? | ペイロード | 送信するデータの本体 |

@payloadは、メッセージを書き込む時のペイロードの配列、@r_payloadはメッセージを読み込む時のペイロードの配列である。

message\_defs()は、メッセージの定義の一覧を返す関数であり、ラムダ式をうまく使うことで、1つの定義から「Rubyの連想配列→メッセージ（バイナリ）」と、「メッセージ（バイナリ）→Rubyの連想配列」の処理を行うことのできる仕組みとなっている。

      def message_defs
        # 中略
        return @message_defs = {
          :version => [
            [:version,   uint32],
            [:services,  uint64],
            [:timestamp, uint64],
            [:your_addr, net_addr],
            [:my_addr,   net_addr],
            [:nonce,     uint64],
            [:agent,     string],
            [:height,    uint32],
            [:relay,     relay_flag]
          ],
          :verack => [],
          :mempool => [],
          :addr => [[:addr, array.curry[net_addr]]],
          :inv  => [[:inventory,  array.curry[inv_vect]]],
          :merkleblock => [
            [:hash,        block_hash],
            [:version,     uint32],
            [:prev_block,  hash256],
            [:merkle_root, hash256],
            [:timestamp,   uint32],
            [:bits,        uint32],
            [:nonce,       uint32],
            [:total_txs,   uint32],
            [:hashes,      array.curry[hash256]],
            [:flags,       string]
          ],
          :tx => [
            [:hash,      tx_hash],
            [:version,   uint32],
            [:tx_in,     array.curry[tx_in]],
            [:tx_out,    array.curry[tx_out]],
            [:lock_time, uint32]
          ],
          :filterload => [
            [:filter,     string],
            [:hash_funcs, uint32],
            [:tweak,      uint32],
            [:flag,       uint8]
          ],
          :getblocks => [
            [:version,       uint32],
            [:block_locator, array.curry[hash256]],
            [:hash_stop,     hash256]
          ],
          :getdata => [[:inventory, array.curry[inv_vect]]]
        }
      end

それぞれの型を定義するラムダ式は、第一引数に:readをつけて呼ばれると読み込み関数、:writeをつけて呼ばれると書き込み関数として働くようになっている。

基本の構成要素の中で説明が必要なのはinteger型ぐらいだろうか。

        integer = lambda do |rw, val = nil|
          case rw
          when :read
            top = uint8.call(:read)
    
            if top < 0xfd then
              return top
            elsif top == 0xfd then
              return uint16.call(:read)
            elsif top == 0xfe then
              return uint32.call(:read)
            elsif top == 0xff then
              return uint64.call(:read)
            end
    
          when :write
            if val < 0xfd then
              uint8.call(:write, val)
            elsif val <= 0xffff then
              uint8.call(:write, 0xfd)
              uint16.call(:write, val)
            elsif val <= 0xffffffff then
              uint8.call(:write, 0xfe)
              uint32.call(:write, val)
            else
              uint8.call(:write, 0xff)
              uint64.call(:write, val)
            end
    
          end
        end

integer型は可変長の符号なし整数であり、先頭のバイトによって長さが示される。この型は、Bitcoin Wikiなどの資料では、var_int型と呼ばれている。

* 0xfdより小さい→先頭のバイトそのものが値で、1バイト(8bit)
* 0xfd→その直後の2バイト(16bit)
* 0xfe→その直後の4バイト(32bit)
* 0xff→その直後の8バイト(64bit)

string型は、先頭のinteger型で以降に続く文字列の長さが示されている、可変長の文字列型である。

### ハンドシェイク（version・verack）

    Usage: ruby bcwallet.rb <command> [<args>]
    commands:
        generate <name>             generate a new Bitcoin address
        list                        show list for all Bitcoin addresses
        export <name>               show private key for the Bitcoin address
        balance                     show balances for all Bitcoin addresses
        send <name> <to> <amount>   transfer coins to the Bitcoin address

上記はbcwallet.rbを無引数で起動した時のUsageである。bcwallet.rbはruby bcwallet.rb balanceとして実行されると、自動的にブロックチェーンの同期をはじめる。この時のプログラムの流れを順に追っていこう。

	# BCWallet#run
        when 'balance'
          STDERR.print "loading data ...\r"
          @network = Network.new(@keys, @data_file_name)
    
          @network.sync()
    
          wait_for_sync()
    
          puts 'Balances for available Bitcoin addresses: '
    
          balance = @network.get_balance()
          balance.each do |addr, satoshi|
            puts "    #{ addr }: #{ sprintf('%.8f', Rational(satoshi, 10**8)) } BTC"
          end

BCWalletクラスはコマンドライン引数を処理し、同ディレクトリの鍵ファイル（Testnetならkeys\_testnet、でなければkeys）を読んだ上で、鍵データを渡してNetworkクラスを作成し、Network#syncを実行する。

Network#sync()はネットワーク通信用のスレッドを新たに作成した上で、直ちにプログラムに戻る。そこで、BCWalletクラス側では、Network#sync\_finished?がtrueになるのを、sleepをはさんでひたすら待ち続けながら、Network#statusの内容を画面に表示する(wait\_for\_sync())。同期が終了したら、Network#get\_balance()で残高のデータを得て、それを画面に表示する。

      def sync
        Thread.abort_on_exception = true
        @is_sync_finished = false
        t = Thread.new do
    
          unless @socket then
            @status = 'connection establishing ... '
    
            @socket = TCPSocket.open(HOST, IS_TESTNET ? 18333 : 8333)
    
            send_version()
          end
    
          if @created_transaction then
            @status = 'announcing transaction ... '
    
            send_transaction_inv()
          end
    
          loop do
            break if dispatch_message()
          end
    
          @is_sync_finished = true
        end
        t.run
      end

他のアドレスに向かってコインを振り込む時は、Network#sendで送信先や金額などを指定してから、同様にNetwork#syncする（後述）。@created\_transactionはNetwork#sendがセットする変数である。

syncが呼ばれた時、ソケットが存在しない場合、ただちにHOSTに接続して（Testnetならポート18333、Mainなら8333）、バージョンメッセージを送信し(send\_version())、メッセージループに入る(dispatch\_message())。メッセージループは、これ以上メッセージを受信する必要のない時にtrueを返す。


<div class="tip"><p>HOSTはデフォルトではlocalhostである。bcwallet.rbのような、ルールを守らないクライアントが外のノードと通信するとよくないと思うので、極力自分のところでBitcoin-Qtを-testnetで起動した所につないで遊んでもらいたい。</p><p>Satoshi Clientの初期ノード探索は、若いバージョンの頃はIRCを用いた「面白い」物となっていたが、今は開発者の立てているノードにつなぎに行ってそこからaddrメッセージを受け取るだけなので特筆すべき点はない。</p><p>話は脱線するが、Satoshi Nakamotoが言及する技術はIRCやUsenet、それにハードディスクの容量を論文で気にしていたりと、総合して見ると明らかに数世代以上前の感があり、さらにはSatoshi ClientのソースはシステムハンガリアンでC++なのにvectorに頻繁にmemcpyしていたりなど、いかにもかなり昔からこの世界に居る技術者っぽさが漂っているが、読者の方々はいかが思われるだろうか。こういった点から謎の人物について思いをはせるのも良いのかもしれない。</p></div>

      def dispatch_message
        message = read_message()
    
        case message[:command]
        when :version
          # 最後のブロックの高さ
          @data[:last_height] = message[:height]
          save_data
    
          write_message({:command => :verack})
    
        when :verack
          # ハンドシェイク完了
    
ハンドシェイクの手順は以下の通りである。（[Bitcoin Wikiの記述](https://en.bitcoin.it/wiki/Version_Handshake)）

* 接続者(A)がまずversionメッセージを接続先(B)に送信（そうするまで被接続者は何も送ってこない）
* A←B versionメッセージを送り返す（プロトコルのバージョンを二者のうち小さい方にあわせる）
* A→B versionメッセージの内容を確認してverackを送り返す
* A←B verackを送り返す


versionメッセージには以下のような情報が含まれている。
verackは、ボディー（ペイロード）が無く、メッセージ名だけのメッセージである。

	  # message_defs()
          :version => [
            [:version,   uint32],
            [:services,  uint64],
            [:timestamp, uint64],
            [:your_addr, net_addr],
            [:my_addr,   net_addr],
            [:nonce,     uint64],
            [:agent,     string],
            [:height,    uint32],
            [:relay,     relay_flag]
          ],
          :verack => [],

      # 中略

      def send_version
        write_message({
          :command => :version,
    
          :version   => PROTOCOL_VERSION,
    
          # 完全なブロックを相手に送れないので0
          :services  => 0,
    
          :timestamp => Time.now.to_i,
    
          :your_addr => nil, # 本当はちゃんと書かないといけないけどテキトーでも
          :my_addr   => nil, # 相手クライアントから怒られないから省略
          
          :nonce     => (rand(1 << 64) - 1), # A random number.
    
          :agent     => '/bcwallet.rb:1.00/', # エージェントの名前
          :height    => (@data[:blocks].length - 1), # 所持しているブロックの高さ
    
          # filterloadするまでいかなるinvも送信しない
          :relay     => false
        })

        return
      end

versionメッセージの内容はかなり適当でもあまりSatoshi Clientは弾き返したりしないようであるが、relayフラグだけは重要である。

relayフラグは、上でも述べたBIP 0037で追加されたフラグである。

Bitcoinは全てのトランザクションのデータをブロードキャストで全てのノードに伝言していくが、これは、相手クライアントの意志と関係なくinvメッセージでハッシュを送り、相手クライアントがそれに対してgetdataを送り返す事で実現されている（後述）。relayフラグを0にセットしないと、相手クライアントはたちまち大量の自分と関係のないinvメッセージを送りつけてくる。

これは、SPVクライアントの望んでいる事ではないので、relayフラグをfalseにセットすることで、filterloadでブルームフィルターをセットするまで全てのinvの送信を止めさせることができる。（そしてfilterloadをセットした後はブルームフィルターに一致したinvしか送られてこない）

<div class="tip"><p><strong>何故bcwallet.rbは他のSPVクライアントより遅いのか</strong> 上のbcwallet.rbを実際に試して頂いた方で、MultiBitなどの他のSPVのBitcoinクライアントを使ったことのある方は、どうしてbcwallet.rbの初回起動時の同期は遅いのかと思われた方も居るかもしれない。</p><p>これは、他のSPVクライアントは、アドレスの作成日時・作成時点での最終ブロックなどの情報を用いて、それより前のブロックのダウンロードを省いているからである。bcwallet.rbは教育用であり、このような複雑な処理を省いて単純化をはかる代わり、はじめに全てのブロックをダウンロードしている。</p></div>

### ブルームフィルターの送信など（filterload・mempool）

引き続き、ハンドシェイク後の動作を見ていこう。

        when :verack
          # ハンドシェイク完了
    
          # ブルームフィルターをセット
          send_filterload()
    
          # メモリープール内のトランザクションを勝手にinvするように
          write_message({:command => :mempool})
    
          # 必要ならばgetblocksを送って、もう終わりならtrueを返す。
          return true if send_getblocks()


send\_filterload()の中は以下の通りである。filterloadコマンドにより、相手クライアントにブルームフィルターのデータを送信し、このフィルターに一致したデータしか送ってこないようにすることができる。

              # message_defs
              :filterload => [
                [:filter,     string],
                [:hash_funcs, uint32],
                [:tweak,      uint32],
                [:flag,       uint8]
              ],

       # 中略

       def send_filterload
        hash_funcs = 10
        tweak = rand(1 << 32) - 1
    
        bf = BloomFilter.new(512, hash_funcs, tweak) 
    
        @keys.each do |_, key|
          bf.insert(key.to_public_key)
          bf.insert(key.to_public_key_hash)
        end
    
        write_message({
          :command => :filterload,
    
          :filter     => bf.to_s,
          :hash_funcs => hash_funcs,
          :tweak      => tweak,
    
          # BLOOM_UPDATE_ALL, updates Bloom filter automatically when the client has found matching transactions.
          :flag       => 1
        })
      end

先に説明したBloomFilterクラスに、所持している鍵の、公開鍵・公開鍵のハッシュを登録していく。

hash\_funcsとBloomFilterのサイズは数学的に効率的となる計算方法が存在するが、ここでは割愛した。興味のある読者は、[BIP 0037](https://github.com/bitcoin/bips/blob/master/bip-0037.mediawiki)に明確な記述があり、また[bitcoinj](https://code.google.com/p/bitcoinj/)のソースコードが参考になるだろう。フィルターサイズの上限は36000バイトである事に注意。フィルターのデータはstring型であり先頭にvar\_intで長さが付加されるのにも注意。

flagも重要である。これは、マッチしたトランザクションに関連するデータを、先方のクライアントが自動で追加していくオプションである。これがないと、仮にアドレスだけをブルームフィルターに登録した際、自分のアドレスがコインを受け取ったトランザクションは引っかかるが、自分のアドレスがコインを消費したトランザクションはフィルターにマッチしない、従って正しい自分のアドレスの残高を割り出せない、といった事態が起こりうる。

mempoolは先方のメモリープールに含まれるトランザクションのinvを自動で送らせるコマンドである。
これにより未承認のトランザクションのデータをすばやく受け取ることができる。

### データのハッシュの取得（getblocks）

getblocksは、自分の所持していないブロック（とそれに関連するトランザクション）のinvを要求するメソッドである。
受信したブロック数が、相手のversionメッセージに書いてあった、相手の所持している最終ブロックの番号を超えたら、send\_getblocksはtrueを返し、止まるようにする。

          # message_defs
          :getblocks => [
            [:version,       uint32],
            [:block_locator, array.curry[hash256]],
            [:hash_stop,     hash256]
          ],

      # 中略

      def send_getblocks
        weight = 50
        perc = (weight * @data[:blocks].length / @data[:last_height]).to_i
        @status = '|' + '=' * perc + '_' * (weight - perc) +
          "| #{(@data[:blocks].length - 1)} / #{@data[:last_height]} "
    
        # @data[:blocks].length includes block #0 while @data[:last_height] does not.
        if @data[:blocks].length > @data[:last_height] then
          save_data()
          return true
        end
    
        if @data[:blocks].empty? then
          send_getdata([{:type => MSG_FILTERED_BLOCK, :hash => @last_hash[:hash]}])
        end
    
        write_message({
          :command => :getblocks,
    
          :version => PROTOCOL_VERSION,
          :block_locator => [@last_hash[:hash]],
          :hash_stop => ['00' * 32].pack('H*')
        })
    
        return false
      end

block\_locatorは自分の所持している最終ブロックのハッシュを指定する。
hash\_stopは、ここまでで送信をストップする、というブロックのハッシュを指定する。(0を指定した場合は500個までinvしてくる）

block\_locatorはここでは1つのハッシュのみを渡すように使われているが、配列である事からも分かるように、実際にはそれよりはるかに複雑な仕組みである。

block\_locatorは本来、自分の信じているブロックチェーンが正しい分岐をたどっているかを抜き打ち検査的にチェックする仕組みである。以下の（現在の版のbcwallet.rbには含まれない）コードをみて欲しい。

    def generate_block_locator_indices(height)
      res = []
  
      step = 1
      while height > 0
        step *= 2 if res.length >= 10
        res.push height
        height -= step
      end
  
      res.push 0
  
      return res
    end

あなたが持っている中で最後のブロックの高さ（つまり、genesis block（最初のブロック）から数えた番号）がheightだとして、本来block\_locatorは、generate\_block\_locator\_indices()の指し示す高さのブロックのハッシュを、全て含まなければならない。

と、言われてもよく分からないだろうが、小さい数でテストしてみよう。height = 500とする。

    > generate_block_locator_indices(500)
    => [500, 499, 498, 497, 496, 495, 494, 493, 492, 491, 490, 488, 484, 476, 460, 428, 364, 236, 0]

500番目、499番目、498番目…と順に番号が下っていく中で、10個を超えると指数関数的に番号が下っていく。（Bitcoin Wikiでは「最初は濃く、次第にまばらに」と表現されている）

これにより、少ない個数のハッシュで、効果的に自分の居るブロックチェーンの分岐の位置を相手に伝えることができる。相手クライアントは、こちら側が誤ったブランチに居る事が分かれば、block\_locatorの内容は無視して1番目のブロックからの情報をこちらに返す。

### データの取得（inv・getdata）

Bitcoinは御存知の通りP2Pの仕組みを取っているため、サーバー・クライアントモデルのような、誰が誰に情報を教えると言った役割分担は存在しない。したがって、任意のクライアントが任意のクライアントに自分の持っている情報を教えうるわけであるが、情報を教えるにあたって、相手がその情報を既に知っているかどうかにかかわらず、常に情報全体を送信していたら、ネットワークはたちまちパンクしてしまうだろう。したがってBitcoinでは、情報の本体を送信する前に、そのハッシュをinvメッセージとして相手クライアントに送り、相手クライアント側から必要な時にはgetdataメッセージを送って情報の本体を要求するという手順を取る。

        inv_vect = lambda do |rw, val = nil|
          case rw
          when :read
            type = uint32.call(:read)
            hash = hash256.call(:read)
            return {:type => type, :hash => hash}
          when :write
            uint32.call(:write, val[:type])
            hash256.call(:write, val[:hash])
          end
        end

      # 中略

          :inv  => [[:inventory,  array.curry[inv_vect]]],
          :getdata => [[:inventory, array.curry[inv_vect]]]

      # 中略

      MSG_TX = 1
      MSG_BLOCK = 2
      MSG_FILTERED_BLOCK = 3

      # 中略
        when :inv
          send_getdata message[:inventory]
    
	  # 全部のデータを受け取ったか判定できるように、送ったgetdataの数を覚えておく
          @requested_data += message[:inventory].length

      # 中略

      def send_getdata(inventory)
        write_message({
          :command => :getdata,
    
          :inventory => inventory.collect do |elm|
            # receive merkleblock instead of usual block
            {:type => (elm[:type] == MSG_BLOCK ? MSG_FILTERED_BLOCK : elm[:type]),
             :hash => elm[:hash]}
          end
        })
    
        return
      end

様々な所からコードを抜粋した。invもgetdataも本体はinv\_vectの配列である。inv\_vectはデータのハッシュ値とデータのタイプを含む。
データのタイプには、MSG\_TXとMSG\_BLOCK、およびBIP0037で追加されたMSG\_FILTERED\_BLOCKが存在する。
MSG\_TXはtx、MSG\_BLOCKはblockを返すのに対して、MSG\_FILTERED\_BLOCKはmerkleblockを返す。merkleblockは、後述するように、ブルームフィルターに一致したトランザクションを検証するのに必要な、ハッシュ木のノードの情報を含んだブロックで、やはりBIP0037で定義されたメッセージである。

### トランザクションとハッシュ木ブロック（tx・merkleblock）

getdataによってtxメッセージやmerkleblockメッセージを受信する。

          :merkleblock => [
            [:hash,        block_hash],
            [:version,     uint32],
            [:prev_block,  hash256],
            [:merkle_root, hash256],
            [:timestamp,   uint32],
            [:bits,        uint32],
            [:nonce,       uint32],
            [:total_txs,   uint32],
            [:hashes,      array.curry[hash256]],
            [:flags,       string]
          ],
          :tx => [
            [:hash,      tx_hash],
            [:version,   uint32],
            [:tx_in,     array.curry[tx_in]],
            [:tx_out,    array.curry[tx_out]],
            [:lock_time, uint32]
          ],

ここで、ブロックとトランザクションのハッシュの計算方法を確認しておきたい。:hashは、write\_messageの時には単純に無視され、read\_messageで作成される、仮想的な要素である。

block\_hashやtx\_hashの実装はこのようになっている。

        block_hash = lambda do |rw, val = nil|
          case rw
          when :read
            return Key.hash256(@r_payload[0, 80])
          end
        end
    
        tx_hash = lambda do |rw, val = nil|
          case rw
          when :read
            return Key.hash256(@r_payload)
          end
        end

txのハッシュは単純にトランザクションのデータ全体についてのハッシュだが、block・merkeblockなどのハッシュは、そのうちのヘッダー部分、つまり先頭80バイトの、nonceまでだけのハッシュである事に注意する。

このブロックのハッシュが[Bitcoinの仕組み](design.html)でも述べたproof-of-workに使われるハッシュである。実際のデータではリトル・エンディアンで配置されているが、.reverseしてunpackするとたしかに00000abc....といった風なハッシュ値が見えてくる。

（ブロックを用いたトランザクションの検証についてはbcwallet.rbの実装と共に加筆予定）

txのlock\_timeは現在のバージョンでは使われていない物で、今は常に0である。
versionはPROTOCOL_VERSIONとも異なる何らかのバージョンである。

### トランザクションをもっと詳しく

そろそろ、トランザクションの作成にも多少意識を向けつつ、tx\_inとtx\_outの中身をみていこう。

        outpoint = lambda do |rw, val = nil|
          case rw
          when :read
            hash = hash256.call(:read)
            index = uint32.call(:read)
            return { :hash => hash, :index => index }
          when :write
            hash256.call(:write, val[:hash])
            uint32.call(:write, val[:index])
          end
        end

        tx_in = lambda do |rw, val = nil|
          case rw
          when :read
            previous_output = outpoint.call(:read)
            signature_script = string.call(:read)
            sequence = uint32.call(:read)
            return { :previous_output => previous_output,
                     :signature_script => signature_script, :sequence => sequence }
          when :write
            outpoint.call(:write, val[:previous_output])
            string.call(:write, val[:signature_script])
            uint32.call(:write, val[:sequence])
          end
        end
    
        tx_out = lambda do |rw, val = nil|
          case rw
          when :read
            value = uint64.call(:read)
            pk_script = string.call(:read)
            return { :value => value, :pk_script => pk_script }
          when :write
            uint64.call(:write, val[:value])
            string.call(:write, val[:pk_script])
          end
        end

tx\_inは入力となるトランザクションの情報を含む型である。sequenceは今は使われていないので常にUINT\_MAXである。
previous\_outputが具体的な前のトランザクションのハッシュと、前のトランザクションの何番目のtx\_outに対応するかを含む。
signature\_scriptの作成方法は非常にまどろっこしいが後ほどトランザクションの作成の節で説明する。

tx\_outはトランザクションの出力先である。valueは出力の額で単位はsatoshi、pk\_scriptは公開鍵の「スクリプト」([Bitcoin Wiki](https://en.bitcoin.it/wiki/Script))である。

Bitcoinは多様な決済手段や多様な電子署名アルゴリズムのサポートを将来的に実現するため、「出力先」の指定方法・電子署名の検証方法はかなりの柔軟性を持った作りになっている。この柔軟性を実現させているのが、「スクリプト」で、簡易的なスタック言語のバイトコードを用いて電子署名の検証を行うようになっている。

しかし現状では、ほとんど定型のスクリプトしか使われていないため、bcwallet.rbではこれのみをサポートすることとする。
（具体的なスクリプトの実行の様子や、これに起因するBitcoinの問題については、[トランザクション展性](malleability.html)で解説）

      def extract_public_key_hash_from_script(script)
        # OP_DUP OP_HASH160 (public key hash) OP_EQUALVERIFY OP_CHECKSIG
        unless script[0, 3]  == ['76a914'].pack('H*') &&
               script[23, 2] == ['88ac'].pack('H*') &&
               script.length == 25 then
          raise 'unsupported script format' 
        end
    
        return script[3, 20]
      end

同期が終わった後、BCWalletクラスはNetwork#get\_balanceを呼び出してアドレスごとの残高を取得し、最後は画面に出力する。

      def get_balance
        balance = {}
        @keys.each do |addr, _|
          balance[addr] = 0
        end
    
        set_spent_for_tx_outs()
    
        @data[:txs].each do |tx_hash, tx|
          @keys.each do |addr, key|
            public_key_hash = key.to_public_key_hash
    
            tx[:tx_out].each do |tx_out|
              # The tx_out was already spent
              next if tx_out[:spent]
    
              if extract_public_key_hash_from_script(tx_out[:pk_script]) == public_key_hash then
                balance[addr] += tx_out[:value]
              end
            end
          end
        end
    
        return balance
      end

公開鍵のハッシュが自分の物と一致していてかつ消費されていないトランザクションなら残額に追加する、という単純な処理である。

set\_spent\_for\_tx\_outsは、そのtx\_outがすでに他のtxで消費されていたら:usedという内部フラグを立てる関数である。

本来であればこのあたりでmerkletreeを見てトランザクションがブロックチェーンに含まれているか否かを判定するべきである。（加筆予定）


### トランザクションの作成・電子署名

トランザクションを送信する時は、BCWalletはまずNetwork#sendで送信先や送信元のキー・コインの額などを指定し、その後やはりNetwork#syncする。

この時のNetwork#syncは、@created\_transactionのハッシュをinvしてgetdataにtxを返しているという、先に説明した流れを逆側の立場から行っているだけなので、以降の話はNetwork#sendの内部の話に絞る。

      # 
      # コインを指定したアドレスに送る
      # from_key = コインの送信元のキーのオブジェクト（Keyクラスのインスタンス）
      # to_addr  = 受信するアドレスの文字列
      # transaction_fee = 取引手数料
      #
      def send(from_key, to_addr, amount, transaction_fee = 0)
        to_addr_decoded = Key.decode_base58check(to_addr)
    
        raise "invalid address" if to_addr_decoded[:type] != :public_key
    
        public_key_hash = from_key.to_public_key_hash
    
        set_spent_for_tx_outs()
    
 過去のトランザクションの中で、
 
 * そのアドレスに向けたトランザクションで
 * 未だ使用されていない

 物を、次々とtx_inに追加していく。これを、送信額として足りるまで続ける。

        total_satoshis = 0
        tx_in = []
        @data[:txs].each do |tx_hash, tx|
          break if total_satoshis >= amount
    
          matched = nil
          pk_script = nil
    
          tx[:tx_out].each_with_index do |tx_out, index|
            next if tx_out[:spent]
    
            if extract_public_key_hash_from_script(tx_out[:pk_script]) == public_key_hash then
              total_satoshis += tx_out[:value]
              matched = index
              pk_script = tx_out[:pk_script]
              break
            end
          end
    
          if matched then
            tx_in.push({ :previous_output => { :hash => tx[:hash], :index => matched },
                         :signature_script => '',
                         :sequence => ((1 << 32) - 1),
    
                         # 送信データには含まれないが、電子署名の作成に使う
                         :pk_script => pk_script })
          end
        end

余った額が「おつり」（payback）として自分宛てのtx\_outに追加される。pk\_scriptは先に説明した通りである。

        payback = total_satoshis - amount - transaction_fee
    
        raise "you don't have enough balance to pay" unless payback >= 0
    
        prefix = ['76a914'].pack('H*') # OP_DUP OP_HASH160 [length of the address]
        postfix = ['88ac'].pack('H*')  # OP_EQUALVERIFY OP_CHECKSIG
        
        tx_out = [{ :value => amount,  :pk_script => (prefix + to_addr_decoded[:data] + postfix) },
                  { :value => payback, :pk_script => (prefix + public_key_hash + postfix) }]
    
        @created_transaction = {
          :command => :tx,
    
          :version => 1,
          :tx_in => tx_in,
          :tx_out => tx_out,
          :lock_time => 0
        }

ここから、電子署名の構築に入るが、非常に分かりづらい上に資料も発見しづらいので注意する。Bitcoin Wikiでは[OP_CHECKSIG](https://en.bitcoin.it/wiki/OP_CHECKSIG)に唯一書いてあるが読みづらい。

	# ここまでで、電子署名抜きのデータを作成したので電子署名を以下で生成する。
     
        signatures = []
    
        tx_in.each_with_index do |tx_in_elm, i|
	  # 元のデータが壊れないように必要最小限の深さだけコピー
          duplicated = @created_transaction.dup
          duplicated[:tx_in] = duplicated[:tx_in].dup
          duplicated[:tx_in][i] = duplicated[:tx_in][i].dup

電子署名の対象となるデータは、以下の手順で構築された、「特殊な」トランザクション全体のハッシュ(Hash256)である。

まず、署名したい部分のtx\_inのsignature\_scriptを、対応するtx\_outの:pk\_scriptで埋め、それ以外のsignature\_scriptは全て空欄とする。なお、各signature\_scriptのstringの先頭の、var\_intも連動して0になるので注意する。[Bitcoin WikiのOP_CHECKSIGの項目](https://en.bitcoin.it/wiki/OP_CHECKSIG)にArmory（というBitcoinクライアント）の作者が描いた図がある。

	  # 対応するtx_outの:pk_scriptで埋める（他のtx_inのsignature_scriptは空欄）
          duplicated[:tx_in][i][:signature_script] = tx_in_elm[:pk_script]
    
          serialize_message(duplicated)

	  # @payloadにシリアライズされたデータが入る

さらにそこにハッシュ種別コード（意味についてはWiki参照のこと）を末尾に**4バイト**で付加し、全体でHash256を取る。

          # hash256 includes type code field (see the figure in the URL above)
          verified_str = Key.hash256(@payload + [1].pack('V'))
    
それをはじめて手元の鍵で電子署名する。

          signatures.push from_key.sign(verified_str)
        end
    
しかし、signature\_scriptも同様にスクリプトシステムの一部なので、普通に作成したsignatureを貼るだけではダメである。さらに、冷静になって思い出して欲しいが、他ノードは未だあなたの公開鍵のハッシュしか知らないのであり、公開鍵本体も必要である。

これらを、＜電子署名+種別コード（**今度はここでは1バイト**）＞＜公開鍵＞の順でsignature\_script格納するが、それぞれの頭に長さを付与しなければならない。そしてこれはvar\_int型では**ない**。また、電子署名＋種別コード1バイトなので、signature.lengthに1を足している。

        signatures.each_with_index do |signature, i|
          @created_transaction[:tx_in][i][:signature_script] =
            [signature.length + 1].pack('C') + signature + [1].pack('C') +
            [from_key.to_public_key.length].pack('C') + from_key.to_public_key
        end
    
        @status = ''
    
        return
      end

ようやっとこれで電子署名が作成できた。あとは、これをinv→getdata→txのやりとりで送信すれば、あなたのトランザクションは送信できたということになる。

### まとめ

ここまでを通して、Bitcoinは、実際に実装するにあたっても決して難しい技術ではないという事が分かったかと思う。

しかしながら、どのクライアントにしても、Bitcoinクライアントの使い勝手は洗練されているとは言い難いのが実情であるし、ネットワーク通信部分はほとんどSatoshi Client系の実装（Bitcoin-Qt, bitcoind, Armory, Electrum?など）系の実装かbitcoinj系の実装（MultiBit, Bitcoin Walletなど）の二つのみが使われていて、実装にしろ資料・仕様書にしろ全く出揃っていないという現実がある。

しかし、これは裏を返せばチャンスではないだろうか？是非これを読まれたやる気のある方は、使いやすくきれいなBitcoinクライアントの実装でBitcoin界を改革してほしいと思う。

「[トランザクション展性とは](malleability.html)」につづく
