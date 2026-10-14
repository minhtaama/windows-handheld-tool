// Standard QWebChannel client implementation
export function QWebChannel(transport, initCallback) {
  if (typeof transport !== "object" || typeof transport.send !== "function") {
    console.error("The QWebChannel transport object is invalid or not available.");
    return;
  }

  const channel = this;
  this.transport = transport;
  this.registeredObjects = {};
  this.objects = {};

  this.send = function (data) {
    if (typeof data !== "string") {
      data = JSON.stringify(data);
    }
    channel.transport.send(data);
  };

  this.transport.onmessage = function (message) {
    let data = message.data;
    if (typeof data === "string") {
      data = JSON.parse(data);
    }
    switch (data.type) {
      case 1: // signal
        channel.handleSignal(data);
        break;
      case 2: // response
        channel.handleResponse(data);
        break;
      case 3: // property update
        channel.handlePropertyUpdate(data);
        break;
      case 4: // init
        channel.handleInit(data, initCallback);
        break;
    }
  };

  this.execCallbacks = {};
  this.execId = 0;

  this.exec = function (data, callback) {
    if (!callback) {
      channel.send(data);
      return;
    }
    channel.execId++;
    channel.execCallbacks[channel.execId] = callback;
    data.id = channel.execId;
    channel.send(data);
  };

  this.handleResponse = function (data) {
    if (data.id in channel.execCallbacks) {
      channel.execCallbacks[data.id](data.data);
      delete channel.execCallbacks[data.id];
    }
  };

  this.handleSignal = function (data) {
    const object = channel.objects[data.object];
    if (object) {
      object.signalEmitted(data.signal, data.args);
    }
  };

  this.handlePropertyUpdate = function (data) {
    for (const i in data.data) {
      const property = data.data[i];
      const object = channel.objects[property.object];
      if (object) {
        object.propertyUpdate(property.signals, property.properties);
      }
    }
  };

  this.handleInit = function (data, callback) {
    for (const objectName in data.data) {
      channel.objects[objectName] = channel.createObject(objectName, data.data[objectName]);
    }
    if (callback) {
      callback(channel);
    }
  };

  this.createObject = function (name, data) {
    const obj = {
      _signals: {},
      signalEmitted: function (signalName, args) {
        if (this._signals[signalName]) {
          for (let i = 0; i < this._signals[signalName].length; i++) {
            this._signals[signalName][i].apply(this, args);
          }
        }
      },
      propertyUpdate: function (signals, properties) {
        for (const propName in properties) {
          this[propName] = properties[propName];
        }
        for (const signalName in signals) {
          this.signalEmitted(signalName, signals[signalName]);
        }
      }
    };

    // Methods
    for (let i = 0; i < data.methods.length; ++i) {
      const methodName = data.methods[i][0];
      obj[methodName] = (function (m) {
        return function () {
          const args = Array.prototype.slice.call(arguments);
          let callback = null;
          if (args.length > 0 && typeof args[args.length - 1] === "function") {
            callback = args.pop();
          }
          channel.exec({
            type: 5, // invokeMethod
            object: name,
            method: m,
            args: args
          }, callback);
        };
      })(methodName);
    }

    // Signals
    for (let i = 0; i < data.signals.length; ++i) {
      const signalName = data.signals[i][0];
      obj[signalName] = {
        connect: function (callback) {
          if (!obj._signals[signalName]) {
            obj._signals[signalName] = [];
          }
          obj._signals[signalName].push(callback);
        },
        disconnect: function (callback) {
          if (obj._signals[signalName]) {
            const idx = obj._signals[signalName].indexOf(callback);
            if (idx !== -1) {
              obj._signals[signalName].splice(idx, 1);
            }
          }
        }
      };
    }

    // Properties
    for (const propName in data.properties) {
      obj[propName] = data.properties[propName];
    }

    return obj;
  };

  // Start initialization handshake
  this.send({ type: 0 });
}
