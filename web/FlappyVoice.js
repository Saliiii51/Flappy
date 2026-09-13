/* FlappyVoice: 2 kişilik oda için P2P sesli sohbet (WebRTC).
 * Sinyalleşme oyun sunucusu üzerinden (voice_* mesajları), ses peer-to-peer.
 * Godot kontratı:
 *   window.FLAPPY_WS_URL  -> sinyal sunucusu (oyunla aynı)
 *   FlappyVoice.start(roomCode, isCaller) / .stop() / .setMuted(m)
 *   FlappyVoice.state -> "off" | "calling" | "live" | "error"
 */
window.FlappyVoice = (function () {
	"use strict";

	var STUN = [{ urls: "stun:stun.l.google.com:19302" }];
	// TURN yedeği (simetrik NAT / mobil veri için). Ücretsiz OpenRelay.
	var TURN = [
		{ urls: "turn:openrelay.metered.ca:80", username: "openrelayproject", credential: "openrelayprojectpassword" },
		{ urls: "turn:openrelay.metered.ca:443", username: "openrelayproject", credential: "openrelayprojectpassword" }
	];
	var ICE_SERVERS = STUN.concat(TURN);

	var state = "off";
	var pc = null;
	var ws = null;
	var stream = null;
	var remoteAudio = null;
	var room = null;
	var isCaller = false;
	var muted = false;
	var onState = null;

	function setState(s) {
		state = s;
		if (typeof onState === "function") {
			try { onState(s); } catch (e) {}
		}
	}

	function send(o) {
		if (ws && ws.readyState === 1) {
			try { ws.send(JSON.stringify(o)); } catch (e) {}
		}
	}

	function closePeer() {
		if (pc) {
			try { pc.close(); } catch (e) {}
			pc = null;
		}
		if (remoteAudio) {
			try { remoteAudio.srcObject = null; } catch (e) {}
		}
	}

	function makeOffer() {
		if (!pc) return Promise.resolve();
		return pc.createOffer()
			.then(function (offer) { return pc.setLocalDescription(offer); })
			.then(function () {
				send({ type: "voice_offer", room: room, sdp: pc.localDescription });
			});
	}

	function handleSignal(m) {
		if (!m || !pc) return Promise.resolve();
		var t = m.type;
		if (t === "voice_hello" && isCaller) {
			return makeOffer().catch(function () { setState("error"); });
		}
		if (t === "voice_roster" && isCaller && m.peers >= 1) {
			return makeOffer().catch(function () { setState("error"); });
		}
		if (t === "voice_offer" && !isCaller) {
			return pc.setRemoteDescription(new RTCSessionDescription(m.sdp))
				.then(function () { return pc.createAnswer(); })
				.then(function (answer) { return pc.setLocalDescription(answer); })
				.then(function () {
					send({ type: "voice_answer", room: room, sdp: pc.localDescription });
				})
				.catch(function () { setState("error"); });
		}
		if (t === "voice_answer" && isCaller) {
			return pc.setRemoteDescription(new RTCSessionDescription(m.sdp))
				.catch(function () { setState("error"); });
		}
		if (t === "voice_ice") {
			try {
				var c = m.candidate;
				return pc.addIceCandidate(new RTCIceCandidate(c)).catch(function () {});
			} catch (e) { return Promise.resolve(); }
		}
		if (t === "voice_peer_left") {
			closePeer();
			if (state === "live" || state === "calling") setState("calling");
			return Promise.resolve();
		}
		return Promise.resolve();
	}

	function connectSignal() {
		var url = window.FLAPPY_WS_URL || null;
		if (!url) { setState("error"); return; }
		try {
			ws = new WebSocket(url);
		} catch (e) { setState("error"); return; }
		ws.onopen = function () { send({ type: "voice_join", room: room }); };
		ws.onmessage = function (ev) {
			var m = null;
			try { m = JSON.parse(ev.data); } catch (e) { return; }
			handleSignal(m);
		};
		ws.onclose = function () { ws = null; };
		ws.onerror = function () {};
	}

	function start(roomCode, caller) {
		if (state === "calling" || state === "live") return Promise.resolve();
		room = String(roomCode || "");
		isCaller = !!caller;
		if (!room) return Promise.resolve();
		setState("calling");
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			setState("error");
			return Promise.resolve();
		}
		return navigator.mediaDevices.getUserMedia({
			audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
		}).then(function (s) {
			stream = s;
			stream.getTracks().forEach(function (t) { t.enabled = !muted; });
			pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
			stream.getTracks().forEach(function (t) { pc.addTrack(t, stream); });
			pc.onicecandidate = function (ev) {
				if (ev.candidate) {
					var c = ev.candidate.toJSON ? ev.candidate.toJSON() : ev.candidate;
					send({ type: "voice_ice", room: room, candidate: c });
				}
			};
			pc.ontrack = function (ev) {
				if (!remoteAudio) {
					remoteAudio = document.createElement("audio");
					remoteAudio.autoplay = true;
					try { remoteAudio.playsInline = true; } catch (e) {}
					document.body.appendChild(remoteAudio);
				}
				try {
					remoteAudio.srcObject = ev.streams[0];
					var p = remoteAudio.play();
					if (p && p.catch) p.catch(function () {});
				} catch (e) {}
			};
			pc.onconnectionstatechange = function () {
				if (!pc) return;
				var st = pc.connectionState;
				if (st === "connected") setState("live");
				else if (st === "failed") setState("error");
				else if ((st === "disconnected" || st === "closed") && state === "live") setState("calling");
			};
			connectSignal();
		}).catch(function () {
			setState("error");
		});
	}

	function stop() {
		try { send({ type: "voice_leave", room: room }); } catch (e) {}
		if (ws) {
			try { ws.close(); } catch (e) {}
			ws = null;
		}
		closePeer();
		if (stream) {
			try { stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
			stream = null;
		}
		room = null;
		setState("off");
	}

	function setMuted(m) {
		muted = !!m;
		if (stream) {
			try { stream.getAudioTracks().forEach(function (t) { t.enabled = !muted; }); } catch (e) {}
		}
	}

	// Konsoldan tanı için: FlappyVoice.debug()
	function debug() {
		var info = { state: state, room: room, isCaller: isCaller, hasPC: !!pc, hasStream: !!stream };
		if (pc) {
			try {
				info.conn = pc.connectionState || null;
				info.ice = pc.iceConnectionState || null;
				info.signaling = pc.signalingState || null;
			} catch (e) {}
		}
		return info;
	}

	var api = {
		start: start,
		stop: stop,
		setMuted: setMuted,
		debug: debug,
		_handleSignal: handleSignal
	};
	Object.defineProperty(api, "state", { get: function () { return state; } });
	Object.defineProperty(api, "muted", { get: function () { return muted; } });
	Object.defineProperty(api, "onStateChange", { set: function (cb) { onState = cb; } });
	return api;
})();
